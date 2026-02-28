function Rename-NetworkAcl
{
    [Alias('nacl_rn')]
    [CmdletBinding(DefaultParameterSetName = 'NetworkAclName', SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = 'NetworkAclId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]
        $NetworkAclId,

        [Parameter(ParameterSetName = 'NetworkAclName', Mandatory, Position = 0)]
        [string]
        $NetworkAclName,

        [Parameter(Mandatory, Position = 1)]
        [string]
        $NewName
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_acl_name = $NetworkAclName
        $_acl_id   = $NetworkAclId
        $_new_name = $NewName

        # Configure the filter to query the Network ACL.
        $_filter_name  = $_param_set -eq 'NetworkAclId' ? 'network-acl-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'NetworkAclId' ? $_acl_id : $_acl_name

        $_filter = [Amazon.EC2.Model.Filter]@{
            Name   = $_filter_name
            Values = $_filter_value
        }

        # Query the list of Network ACLs to rename first.
        try {
            $_acl_list = Get-EC2NetworkAcl -Verbose:$false -Filter $_filter
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
        if (-not $_acl_list)
        {
            Write-Error "No Network ACLs were found for '$_filter_value'."
            return
        }

        # Loop through each Network ACL to perform the renaming.
        $_acl_list | ForEach-Object {

            # Generate a friendly display string for the Network ACL.
            $_format_acl = $_ | Get-ResourceString `
                -IdPropertyName 'NetworkAclId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            if ($PSCmdlet.ShouldProcess($_format_acl, "Rename Network ACL")) {

                try {
                    New-EC2Tag -Verbose:$false -Tag @{Key = 'Name'; Value = $_new_name} $_.NetworkAclId
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