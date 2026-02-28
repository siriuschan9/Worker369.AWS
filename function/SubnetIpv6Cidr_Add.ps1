<#
.SYNOPSIS
This cmdlet adds an IPv6 CIDR block to a Subnet.
You can specify the Subnet(s) using either the -SubnetId or -SubnetName Parameter.

.PARAMETER SubnetId
The -SubnetId Parameter specifies the Subnet ID.
You can also pass in an array of Subnet IDs.
This parameter supports pipeline inputs.
See example 1.

.PARAMETER SubnetName
The -SubnetName Parameter specifies the Subnet's Name.
See example 2.

.PARAMETER Ipv6Cidr
The -Ipv6Cidr Parameter specifies the IPv6 CIDR block to add to the Subnet.

.EXAMPLE
Add-SubnetIpv6Cidr -SubnetId subnet-1234567890abcdef0 -Ipv6Cidr 2000:3000:4000:5000::/64

This example adds the 2000:3000:4000:5000::/64 CIDR block to the Subnet subnet-1234567890abcdef0.

.EXAMPLE
Add-SubnetIpv6Cidr -SubnetName example-2 -Ipv6Cidr 2000:3000:4000:5000::/64

This example adds the 2000:3000:4000:5000::/64 CIDR block to the Subnet named "example-2".
#>
function Add-SubnetIpv6Cidr
{
    [Alias('subnet_ipv6_add')]
    [CmdletBinding(DefaultParameterSetName = 'SubnetName', SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = 'SubnetId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^subnet-[0-9a-f]{17}$')]
        [string[]]
        $SubnetId,

        [Parameter(ParameterSetName = 'SubnetName', Mandatory, Position = 0)]
        [string[]]
        $SubnetName,

        [Parameter(ParameterSetName = 'SubnetId', Mandatory)]
        [Parameter(ParameterSetName = 'SubnetName', Mandatory, Position = 1)]
        [ValidateScript(
            {
                $_prefix_pattern = "[0-9]|[1-9][0-9]|1[0-1][0-9]|12[0-8]";
                $_hex_pattern    = "[0-9a-fA-F]";
                $_hextet_pattern = "$($_hex_pattern){1,4}";

                $_ipv6_0 = "($($_hextet_pattern):){7}$($_hextet_pattern)";
                $_ipv6_1 = "($($_hextet_pattern):){1,7}:";
                $_ipv6_2 = "($($_hextet_pattern):){1,6}(:$($_hextet_pattern)){1,1}";
                $_ipv6_3 = "($($_hextet_pattern):){1,5}(:$($_hextet_pattern)){1,2}";
                $_ipv6_4 = "($($_hextet_pattern):){1,4}(:$($_hextet_pattern)){1,3}";
                $_ipv6_5 = "($($_hextet_pattern):){1,3}(:$($_hextet_pattern)){1,4}";
                $_ipv6_6 = "($($_hextet_pattern):){1,2}(:$($_hextet_pattern)){1,5}";
                $_ipv6_7 = "($($_hextet_pattern):){1,1}(:$($_hextet_pattern)){1,6}";
                $_ipv6_8 = ":(:$($_hextet_pattern)){1,7}";
                $_ipv6_9 = "::";

                $_ip_pattern = '^(' +
                    $_ipv6_0 + '|' + $_ipv6_1 + '|' + $_ipv6_2 + '|' + $_ipv6_3 + '|' + $_ipv6_4 + '|' +
                    $_ipv6_5 + '|' + $_ipv6_6 + '|' + $_ipv6_7 + '|' + $_ipv6_8 + '|' + $_ipv6_9 + ')$'

                $_cidr_pattern = $_ip_pattern.TrimEnd('$') + "\/($($_prefix_pattern))$";

                if ($_ -match $_cidr_pattern) { $true }
                else {
                    throw [System.Management.Automation.ValidationMetadataException]::new("Invalid Ipv6Cidr.")
                }
            }
        )]
        [string]
        $Ipv6Cidr
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
        $_subnet_id   = $SubnetId
        $_subnet_name = $SubnetName
        $_ipv6_cidr   = $Ipv6Cidr

        # Configure the filter to query the Subnet.
        $_filter_name  = $_param_set -eq 'SubnetId' ? 'subnet-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'SubnetId' ? $_subnet_id : $_subnet_name

        # Query the list of Subnet to remove first.
        try {
            $_subnet_list = Get-EC2Subnet -Verbose:$false -Filter @{Name = $_filter_name; Values = $_filter_value}
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no subnet matched the filter value, exit early.
        if (-not $_subnet_list)
        {
            Write-Error "No Subnet was found for '$_filter_value'."
            return
        }

        # Loop through each Subnet to perform the CIDR addition.
        $_subnet_list | ForEach-Object {

            # Generate a friendly display string for the subnet.
            $_format_subnet = $_ | Get-ResourceString `
                -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            if ($PSCmdlet.ShouldProcess($_format_subnet, 'Add IPv6 CIDR block'))
            {
                try {
                    $_result = Register-EC2SubnetCidrBlock -Verbose:$false `
                        -Ipv6CidrBlock $_ipv6_cidr `
                        -SubnetId $_.SubnetId

                    # Wait for the association to finish.
                    Write-Message -Progress $_cmdlet_name "|- Waiting for association to complete."

                    $_counter = 0;
                    do {
                        Start-Sleep 1; $_counter++

                        $_assoc_set = Get-EC2Subnet -Verbose:$false -Filter @{
                            Name   = 'ipv6-cidr-block-association.association-id'
                            Values = $_result.Ipv6CidrBlockAssociation.AssociationId
                        } |
                        Select-Object -ExpandProperty Ipv6CidrBlockAssociationSet |
                        Where-Object AssociationId -eq $_result.Ipv6CidrBlockAssociation.AssociationId

                        $_state = $_assoc_set.Ipv6CidrBlockState.State

                    } while ($_state -ne 'associated' -and $_counter -le 3)

                    # Return the result to the caller.
                    Write-Message -Output "|- State: $_state."
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