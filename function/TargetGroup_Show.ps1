function Show-TargetGroup
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    [Alias('tg_show')]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('Health')]
        [string]
        $View = 'Health',

        [Amazon.EC2.Model.Filter[]]
        $Filter,

        [ValidateSet('Vpc')]
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
    $_filter           = $Filter
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_where            = $Where
    $_pass_thru        = $PassThru.IsPresent
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    # For easy pick-up.
    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

    $_view_definition = @{
        'Health' = @(
            'TargetGroupName', 'LoadBalancers', 'TargetType', 'TargetPort', 'TargetProtocol',
            'Target', 'AvailabilityZone', 'State', 'Reason'
        )
    }

    $_select_definition = @{
        TargetGroupName = {
            $_.TargetGroupName
        }
        LoadBalancers = {
            $_elb_lookup[$_.TargetGroupArn] | Select-Object -ExpandProperty LoadBalancerName
        }
        TargetType = {
            $_.TargetType
        }
        TargetPort = {
            $_.TargetPort
        }
        TargetProtocol = {
            $_.Protocol
        }
        Target = {
            $_health_lookup[$_.TargetGroupArn] |
            Select-Object -ExpandProperty Target |
            Select-Object -ExpandProperty Id
        }
        AvailabilityZone = {
            $_health_lookup[$_.TargetGroupArn] |
            Select-Object -ExpandProperty Target |
            Select-Object -ExpandProperty AvailabilityZone
        }
        State = {
            $_health_lookup[$_.TargetGroupArn] |
            Select-Object -ExpandProperty TargetHealth |
            Select-Object -ExpandProperty State
        }
        Reason = {
            $_health_lookup[$_.TargetGroupArn] |
            Select-Object -ExpandProperty TargetHealth |
            Select-Object -ExpandProperty Reason
        }
    }

    try {

        Write-Message -Progress $_cmdlet_name 'Fetching Target Groups.'
        $_tg_list = Get-ELB2TargetGroup -Verbose:$false

        # Exit early if there are no target groups.
        if (-not $_tg_list) { return }

        if ($_view -in @('health')) {
            $_health_lookup = @{}
            $_tg_list | ForEach-Object {
                $_health_lookup[$_.TargetGroupArn] = Get-ELB2TargetHealth -Verbose:$false $_.TargetGroupArn
            }
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }
}