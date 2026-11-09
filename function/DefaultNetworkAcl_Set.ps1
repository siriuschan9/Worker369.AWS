
function Set-DefaultNetworkAcl
{
    [CmdletBinding(DefaultParameterSetName = 'NetworkAclName')]
    [Alias('nacl_default')]
    param(
        [Parameter(ParameterSetName = 'NetworkAclId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]
        $NetworkAclId,

        [Parameter(ParameterSetName = 'NetworkAclName', Mandatory, Position = 0)]
        [string]
        $NetworkAclName
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_nacl_name = $NetworkAclName
        $_nacl_id   = $NetworkAclId

        # Configure the filter to query the Network ACL.
        $_filter_name  = $_param_set -eq 'NetworkAclId' ? 'network-acl-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'NetworkAclId' ? $_nacl_id : $_nacl_name

        $_filter = [Amazon.EC2.Model.Filter]@{
            Name   = $_filter_name
            Values = $_filter_value
        }

        # Grab the Network ACL first.
        try {
            $_nacl_list = Get-EC2NetworkAcl -Verbose:$false -Filter $_filter
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no Network ACLs matched the filter value, exit early.
        if (-not $_nacl_list)
        {
            Write-Error "No Network ACLs were found for '$_filter_value'."
            return
        }

        # If multiple Network ACLs matched the filter value, exit early.
        if ($_nacl_list.Count -gt 1)
        {
            Write-Error "Multiple Network ACLs were found for '$_filter_value'. It must match exactly one Network ACL."
            return
        }

        $_nacl = $_nacl_list[0]

        # Save the filtered Network ACL.
        $script:DefaultNetworkAcl = $_nacl

        $_format_nacl = $_nacl | Get-ResourceString `
            -IdPropertyName 'NetworkAclId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

        Write-Message -Output "You are currently working on $_format_nacl."
    }
}

function Get-DefaultNetworkAcl
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    [OutputType([Amazon.EC2.Model.NetworkAcl], ParameterSetName = 'Raw')]
    [OutputType([string], ParameterSetName = 'None')]
    [Alias('nacl_default?')]

    param(
        [Parameter(ParameterSetName = 'Raw')]
        [switch]$Raw
    )

    return $PSCmdlet.ParameterSetName -eq 'Raw' `
        ? $script:DefaultNetworkAcl
        : "$($script:DefaultNetworkAcl | Get-ResourceString -IdPropertyName 'NetworkAclId' -TagPropertyName 'Tags')"
}

function Clear-DefaultNetworkAcl
{
    [CmdletBinding()]
    [Alias('nacl_default_clear')]
    param()

    Clear-Variable -Scope Script DefaultNetworkAcl
}

[Amazon.EC2.Model.NetworkAcl]$script:DefaultNetworkAcl = $null