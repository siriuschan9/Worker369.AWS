
function Set-DefaultRouteTable
{
    [CmdletBinding(DefaultParameterSetName = 'RouteTableName')]
    [Alias('rt_default')]
    param(
        [Parameter(ParameterSetName = 'RouteTableId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]
        $RouteTableId,

        [Parameter(ParameterSetName = 'RouteTableName', Mandatory, Position = 0)]
        [string]
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
        $_rt_name = $RouteTableName
        $_rt_id   = $RouteTableId

        # Configure the filter to query the Route Table.
        $_filter_name  = $_param_set -eq 'RouteTableId' ? 'route-table-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'RouteTableId' ? $_rt_id : $_rt_name

        $_filter = [Amazon.EC2.Model.Filter]@{
            Name   = $_filter_name
            Values = $_filter_value
        }

        # Grab the route table first.
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

        # If multiple Route Tables matched the filter value, exit early.
        if ($_rt_list.Count -gt 1)
        {
            Write-Error "Multiple Route Tables were found for '$_filter_value'. It must match exactly one Route Table."
            return
        }

        $_rt = $_rt_list[0]

        # Save the filtered Route Table.
        $script:DefaultRouteTable = $_rt

        $_format_rt = $_rt | Get-ResourceString `
            -IdPropertyName 'RouteTableId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

        Write-Message -Output "You are currently working on $_format_rt."
    }
}

function Get-DefaultRouteTable
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    [OutputType([Amazon.EC2.Model.RouteTable], ParameterSetName = 'Raw')]
    [OutputType([string], ParameterSetName = 'None')]
    [Alias('rt_default?')]

    param(
        [Parameter(ParameterSetName = 'Raw')]
        [switch]$Raw
    )

    return $PSCmdlet.ParameterSetName -eq 'Raw' `
        ? $script:DefaultRouteTable
        : "$($script:DefaultRouteTable | Get-ResourceString -IdPropertyName 'RouteTableId' -TagPropertyName 'Tags')"
}

function Clear-DefaultRouteTable
{
    [CmdletBinding()]
    [Alias('rt_default_clear')]
    param()

    Clear-Variable -Scope Script DefaultRouteTable
}

[Amazon.EC2.Model.RouteTable]$script:DefaultRouteTable = $null