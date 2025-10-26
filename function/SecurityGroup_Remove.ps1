function Remove-SecurityGroup
{
    [Alias('sg_rm')]
    [CmdletBinding(DefaultParameterSetName = 'TagName', SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ParameterSetName = 'GroupId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^sg-[0-9a-f]{17}$', ErrorMessage = 'Invalid GroupId.')]
        [string[]]
        $GroupId,

        [Parameter(ParameterSetName = 'TagName', Mandatory, Position = 0)]
        [string[]]
        $TagName
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_sg_id   = $GroupId
        $_tag_name = $TagName

        # Configure the filter to query the Security Group.
        $_filter_name  = $_param_set -eq 'GroupId' ? 'group-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'GroupId' ? $_sg_id : $_tag_name

        $_filter = [Amazon.EC2.Model.Filter]@{
            Name   = $_filter_name
            Values = $_filter_value
        }

        # Grab the list of Security Groups first.
        try {
            $_sg_list = Get-EC2SecurityGroup -Verbose:$false -Filter $_filter
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Reposg error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no Security Groups matched the filter value, exit early.
        if (-not $_sg_list)
        {
            Write-Error "No Security Groups were found for '$_filter_value'."
            return
        }

        $_sg_list | ForEach-Object {

            # Generate a friendly display string for the Security Group.
            $_format_sg = $_ | Get-ResourceString `
                -IdPropertyName 'GroupId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            if ($PSCmdlet.ShouldProcess($_format_sg, "Remove Security Group"))
            {
                try {
                    Remove-EC2SecurityGroup -Verbose:$false -Confirm:$false $_.GroupId | Out-Null
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