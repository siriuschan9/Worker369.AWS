function Remove-NetworkAcl
{
    [Alias('nacl_rm')]
    [CmdletBinding(DefaultParameterSetName = 'Name', SupportsShouldProcess, ConfirmImpact = 'High')]
    param (

        [Parameter(ParameterSetName = 'NetworkAclId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^acl-[0-9a-f]{17}$', ErrorMessage = 'Invalid NetworkAclId.')]
        [string[]]
        $NetworkAclId,

        [Parameter(ParameterSetName = 'Name', Mandatory, Position = 0)]
        [string[]]
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
        $_acl_id   = $NetworkAclId
        $_acl_name = $NetworkAclName

        # Configure the filter to query the Network ACL.
        $_filter_name  = $_param_set -eq 'NetworkAclId' ? 'route-table-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'NetworkAclId' ? $_acl_id : $_acl_name

        $_filter = [Amazon.EC2.Model.Filter]@{
            Name   = $_filter_name
            Values = $_filter_value
        }

        # Grab the list of Network ACLs first.
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

        $_acl_list | ForEach-Object {

            # Generate a friendly display string for the Route Table.
            $_format_acl = $_ | Get-ResourceString `
                -IdPropertyName 'NetworkAclId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            if ($PSCmdlet.ShouldProcess($_format_acl, "Remove Network ACL")) {

                try {
                    Remove-EC2NetworkAcl -Verbose:$false -Confirm:$false $_.NetworkAclId
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