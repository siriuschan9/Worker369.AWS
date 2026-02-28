function Rename-SecurityGroup
{
    [Alias("sg_rn")]
    [CmdletBinding(DefaultParameterSetName = 'TagName', SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = 'GroupId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^sg-[0-9a-f]{17}$')]
        [string]
        $GroupId,

        [Parameter(ParameterSetName = 'TagName', Mandatory, Position = 0)]
        [string]
        $TagName,

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
        $_sg_id    = $GroupId
        $_tag_name = $TagName
        $_new_name = $NewName

        # Configure the filter to query the Security Group.
        $_filter_name  = $_param_set -eq 'GroupId' ? 'group-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'GroupId' ? $_sg_id    : $_tag_name

        # Query the list of Security Group to rename first.
        try {
            $_sg_list = Get-EC2SecurityGroup -Verbose:$false -Filter @{Name = $_filter_name; Values = $_filter_value}
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no Security Groups matched the filter value, exit early.
        if (-not $_sg_list)
        {
            Write-Error "No Security Group was found for '$_filter_value'."
            return
        }

        # Loop through each Security Group to perform the renaming.
        $_sg_list | ForEach-Object {

            # Generate a friendly display string for the Security Group.
            $_format_sg = $_ | Get-ResourceString `
                -IdPropertyName 'GroupId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirm prompt.
            if ($PSCmdlet.ShouldProcess($_format_sg, "Rename Security Group"))
            {
                # Call the API to revalue the Name Tag.
                try {
                    New-EC2Tag -Resource $_.GroupId -Tag @{Key = 'Name'; Value = $_new_name} -Verbose:$false
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