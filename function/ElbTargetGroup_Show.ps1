function Show-ElbTargetGroup
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    [Alias('tg_show')]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('Health')]
        [string]
        $View = 'Health',

        [ValidateSet('Vpc', 'State', 'TargetType')]
        [string]
        $GroupBy = 'Vpc',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [ScriptBlock]
        $Where = {$true},

        [switch]
        $PassThru,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # Use snake_case.
    $_view             = $View
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_where            = $Where
    $_pass_thru        = $PassThru.IsPresent
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    # For easy pick-up.
    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name
    $_dash        = $_plain_text ? '-' : "$($PSStyle.Dim)-$($PSStyle.Reset)"

    $_view_definition = @{
        'Health' = @(
            'TargetGroupName', 'LoadBalancers', 'Protocol', 'TargetType', 'Target', 'State', 'AvailabilityZone', 'Vpc'
        )
    }

    $_select_definition = @{
        TargetGroupName = {
            $_.TargetGroupName
        }
        LoadBalancers = {
            $_elb_name_list = foreach ($_elb_arn in $_.LoadBalancerArns) {
                $_elb_lookup[$_elb_arn].LoadBalancerName
            }
            $_elb_name_list ?? $_dash
        }
        TargetType = {
            $_.TargetType
        }
        Protocol = {
            "$($_.Protocol):$($_.Port)"
        }
        Target = {
            $_find_target = $_.TargetType.Value -eq 'instance' `
                ? {
                    param($Target) $_ec2_lookup[$Target.Id] |
                    Get-ResourceString -IdPropertyName 'InstanceId' -TagPropertyName 'Tags' -PlainText:$_plain_text } `
                : {
                    param($Target) $Target.Id }

            $_target_health_list = $_health_lookup[$_.TargetGroupArn]
            foreach ($_target_health in $_target_health_list) {
                & $_find_target($_target_health.Target)
            }
        }
        AvailabilityZone = {
            $_find_az = $_.TargetType.Value -eq 'instance' `
            ? {
                param($Target) $_ec2_lookup[$Target.Id].Placement.AvailabilityZone } `
            : {
                param($Target) $Target.AvailabilityZone }

            $_target_health_list = $_health_lookup[$_.TargetGroupArn]
            foreach ($_target_health in $_target_health_list) {
                & $_find_az($_target_health.Target)
            }
        }
        State = {
            $_health_list = $_health_lookup[$_.TargetGroupArn] | Select-Object -ExpandProperty TargetHealth

            foreach ($_health in $_health_list) {
                $_checked     = $_health.State -eq 'healthy'
                $_description = $_checked ? "$($_health.State)" : "$($_health.State) - $($_health.Reason)"
                New-Checkbox -PlainText:$_plain_text -Description $_description $_checked
            }
        }
        Vpc = {
            $_vpc_lookup[$_.VpcId] |
            Get-ResourceString -IdPropertyName VpcId -TagPropertyName Tags -PlainText:$_plain_text
        }
    }

    try {
        Write-Message -Progress $_cmdlet_name 'Fetching Target Groups Information.'
        $_tg_list = Get-ELB2TargetGroup -Verbose:$false

        # Exit early if there are no target groups.
        if (-not $_tg_list) { return }

        Write-Message -Progress $_cmdlet_name 'Fetching Target Health Information.'
        if ($_view -in @('health')) {

            $_health_lookup = @{}
            $_tg_list | ForEach-Object {
                $_health_lookup[$_.TargetGroupArn] = Get-ELB2TargetHealth -Verbose:$false $_.TargetGroupArn
            }

            $_elb_lookup = Get-ELB2LoadBalancer -Verbose:$false | Group-Object -AsHashTable LoadBalancerArn
        }

        Write-Message -Progress $_cmdlet_name 'Fetching VPC Information.'
        $_vpc_lookup = `
            Get-EC2Vpc -Verbose:$false -Filter @{Name = 'vpc-id'; Values = $_tg_list.VpcId} |
            Group-Object -AsHashTable VpcId

        Write-Message -Progress $_cmdlet_name 'Fetching EC2 Information.'
        $_ec2_lookup = `
            Get-EC2Instance -Verbose:$false -Filter @{
                Name   = 'instance-id'
                Values = ($_health_lookup.Values.Where({$_.Target.Id -match 'i-[0-9a-f]{17}'})).Target.Id
            } |
            Select-Object -ExpandProperty Instances |
            Group-Object -AsHashTable InstanceId
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Apply default sort order.
    if ($_group_by -eq 'Vpc' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(1) # => Sort by Name
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Generate output after sorting and exclusion.
    $_output = $_tg_list `
        | Select-Object $_select_list `
        | Sort-Object   $_sort_list `
        | Select-Object $_project_list `
        | Where-Object  $_where

    # If -PassThru, put the objects in the pipeline.
    if ($_pass_thru) {$_output; return }

    # If EnableHtmlOutput is set, output html markup.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
        return
    }
    # Print out the output to the terminal.
    $_align_left  = @('State')
    $_align_right = @()
    $_output | Format-Column `
        -AlignLeft $_align_left `
        -AlignRight $_align_right `
        -GroupBy $_group_by `
        -PlainText:$_plain_text `
        -NoRowSeparator:$_no_row_separator
}