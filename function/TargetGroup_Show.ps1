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

        }
        AvailabilityZone = {

        }
        State = {

        }
        Reason = {

        }
    }
}