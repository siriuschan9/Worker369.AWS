using namespace System.Collections.Generic

function Write-PrefixList
{
    [CmdletBinding(SupportsShouldProcess)]
    [Alias("pl_write")]
    param (
        [Parameter(ParameterSetName = "PrefixListId", Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^pl-([0-9a-f]{8}|[0-9a-f]{17})$')]
        [string]
        $PrefixListId,

        [Parameter(ParameterSetName = "PrefixListName", Position = 0, Mandatory)]
        [string]
        $PrefixListName,

        [Parameter(ParameterSetName = "PrefixListName", Position = 1, Mandatory)]
        [Parameter(ParameterSetName = "PrefixListId", Mandatory)]
        [string[]]
        $CidrList
    )

    BEGIN
    {
         # For easy pick up.
        $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name
        $_param_set   = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_pl_id     = $PrefixListId
        $_pl_name   = $PrefixListName
        $_cidr_list = $CidrList

        # If caller passed in empty CIDR list, exit early
        if ($_cidr_list.Length -eq 0) {
            return
        }

        # Configure the filter to query the Prefix List.
        $_filter_name  = $_param_set -eq 'PrefixListId' ? 'prefix-list-id' : 'prefix-list-name'
        $_filter_value = $_param_set -eq 'PrefixListId' ? $_pl_id : $_pl_name

        $_filter = [Amazon.EC2.Model.Filter]@{
            Name   = $_filter_name
            Values = $_filter_value
        }

        # Grab the prefix lists first.
        try {
            $_pl_list = Get-EC2ManagedPrefixList -Verbose:$false -Filter $_filter
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If there are no prefix list filtered, exit early
        if (-not $_pl_list) {
            return
        }

        # Determine the IP version of CIDRs in the list.
        $_ipv4, $_ipv6, $_invalid = Get-CidrType $_cidr_list

        # Check if there are multiple IP versions in the list.
        if ($_ipv4.Length -gt 0 -and $_ipv6.Length -gt 0) {
            $PSCmdlet.WriteError("There are multiple IP versions in the CIDR list. Only one version is allowed.")
            return
        }

        # Check for invalid CIDRs in the list.
        if ($_invalid.Length -gt 0) {
            $PSCmdlet.WriteError("There are invalid CIDRs in the list: $($_invalid -join ',')")
            return
        }

        # Determine IP version.
        $_address_family = $_ipv4.Length -gt 0 ? 'IPv4' : 'IPv6'

        if ($_address_family -eq 'IPv4') {
            $_add_entry_list = $_ipv4 | Where-Object {$null -ne $_} | ForEach-Object {
                [Amazon.EC2.Model.AddPrefixListEntry]@{
                    Cidr = $_.Trim() -match '\/([0-9]|[1-2][0-9]|3[0-2])$' ? $_.Trim() : "$($_.Trim())/32"
                }
            }
        }
        else {
            $_add_entry_list = $_ipv6 | Where-Object {$null -ne $_} | ForEach-Object {
                [Amazon.EC2.Model.AddPrefixListEntry]@{
                    Cidr = $_.Trim() -match "\/([0-9]|[1-9][0-9]|1[0-1][0-9]|12[0-8])$" ? $_.Trim() : "$($_.Trim())/128"
                }
            }
        }

        $_pl_list | ForEach-Object {

            $_format_pl = $_ | Get-ResourceString `
                -IdPropertyName 'PrefixListId' -NamePropertyName 'PrefixListName' -StringFormat IdAndName -PlainText

            if ($_.AddressFamily -ne $_address_family) {
                Write-Warning (
                    "$_format_pl uses a different IP version from the CIDR list." + " " +
                    "No changes will be made to this prefix list."
                )
                return
            }

            if ($PSCmdlet.ShouldProcess($_format_pl, "Write CIDR list"))
            {
                try {
                    # Get existing entries to remove.
                    $_remove_entry_list = `
                        Get-EC2ManagedPrefixListEntry -Verbose:$false $_.PrefixListId | ForEach-Object {
                            [Amazon.EC2.Model.RemovePrefixListEntry]@{
                                Cidr = $_.Cidr
                            }
                        }

                    # See if we need to increase the MaxEntries limit.
                    $_max_entries = [int]::Max($_.MaxEntries, $_add_entry_list.Length)

                    if ($_max_entries -gt $_.MaxEntries)
                    {
                        Write-Message -Progress $_cmdlet_name "|- Increasing the Max Entries limit first."
                        Edit-EC2ManagedPrefixList -Verbose:$false -MaxEntry $_max_entries $_.PrefixListId | Out-Null
                    }

                    # Prepare sets for calculating set differences.
                    $_remove_cidr_list = $_remove_entry_list | Select-Object -ExpandProperty Cidr
                    $_add_cidr_list    = $_add_entry_list    | Select-Object -ExpandProperty Cidr

                    # Make sure add and remove entries do not have common CIDRs.
                    $_remove_entry_list = $_remove_entry_list | Where-Object Cidr -NotIn $_add_cidr_list
                    $_add_entry_list    = $_add_entry_list    | Where-Object Cidr -NotIn $_remove_cidr_list

                    if ($_add_entry_list.Length -gt 0 -or $_remove_entry_list.Length -gt 0)
                    {
                        # Add the API to write the prefix list entries.
                        Edit-EC2ManagedPrefixList -Verbose:$false $_.PrefixListId `
                            -AddEntry $_add_entry_list `
                            -RemoveEntry $_remove_entry_list `
                            -CurrentVersion $_.Version `
                        | Out-Null
                    }
                    else
                    {
                        Write-Message -Progress $_cmdlet_name `
                            "|- No modifications made to prefix list - There are no differences between the CIDR lists."
                    }
                }
                catch {
                    # Remove caught exception emitted into $Error list.
                    Pop-ErrorRecord $_

                    # Report error as non-terminating.
                    $PSCmdlet.WriteError($_)
                }
            }

        }
    }
}

function Get-CidrType
{
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string[]]
        $CidrList
    )

    BEGIN
    {
        $_ipv4, $_ipv6, $_invalid = @(), @(), @()
    }

    PROCESS
    {
        # Use snake_case.
        $_cidr_list = $CidrList

        foreach ($_cidr in $_cidr_list) {
            if (Test-IsValidIPv4 $_cidr) {
                $_ipv4 += $_cidr
            }
            elseif (Test-IsValidIPv6 $_cidr) {
                $_ipv6 += $_cidr
            }
            else {
                $_invalid += $_cidr
            }
        }
    }

    END
    {
        @($_ipv4, $_ipv6, $_invalid) # If we don't array-wrap it, powershell returns one flat array.
    }
}