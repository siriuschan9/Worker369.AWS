function Remove-RouteTable
{
    [Alias('rt_rm')]
    [CmdletBinding(DefaultParameterSetName = 'RouteTableName', SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ParameterSetName = 'RouteTableId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^rtb-[0-9a-f]{17}$', ErrorMessage = 'Invalid RouteTableId.')]
        [string[]]
        $RouteTableId,

        [Parameter(ParameterSetName = 'RouteTableName', Mandatory, Position = 0)]
        [string[]]
        $RouteTableName
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_rt_id   = $RouteTableId
        $_rt_name = $RouteTableName

        # Configure the filter to query the Route Table.
        $_filter_name  = $_param_set -eq 'RouteTableId' ? 'route-table-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'RouteTableId' ? $_rt_id : $_rt_name

        $_filter = [Amazon.EC2.Model.Filter]@{
            Name   = $_filter_name
            Values = $_filter_value
        }

        # Grab the list of route tables first.
        try {
            $_rt_list = Get-EC2RouteTable -Verbose:$false -Filter $_filter
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no Route Tables matched the filter value, exit early.
        if (-not $_rt_list)
        {
            Write-Error "No Route Tables were found for '$_filter_value'."
            return
        }

        $_rt_list | ForEach-Object {

            # Generate a friendly display string for the Route Table.
            $_format_rt = $_ | Get-ResourceString `
                -IdPropertyName 'RouteTableId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            if ($PSCmdlet.ShouldProcess($_format_rt, "Remove Route Table"))
            {
                try {
                    Remove-EC2RouteTable -Verbose:$false -Confirm:$false $_.RouteTableId
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