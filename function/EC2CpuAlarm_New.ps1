$Script:DefaultEC2CpuAlarmConfig = @{
    Expression = 'Average(CPUUtilization) > 90p ; 60 ; 3/5 ; missing'
    Dimension  = [Amazon.CloudWatch.Model.Dimension]@{Name = 'InstanceId'; Value = '{InstanceId}'}
    AlarmName  = 'EC2 Status Alarm ({AccountName}/{InstanceName})'
}

<#
.SYNOPSIS
This cmdlet creates a new CPU alarm for a specified EC2 instance.

.DESCRIPTION
This cmdlet creates a new CloudWatch alarm on the CPUUtilization metric with default settings.
The caller must specifiy the instance ID using the InstanceId parameter.

.PARAMETER InstanceId
The instance ID of the EC2 instance to create the CPU alarm for. This parameter is mandatory.

.PARAMETER Expression
A semicolon-delimited expression to configure the alarm settings. The expression is of the following format:
a(b) c d ; e ; f/g ; h
a - Statistic             - Average | Maximum | Minimum | SampleCount | Sum
b - Metric Name           - CPU Utilization
c - Comparison Operator   - > | < | >= | <=
d - Threshold             - 0p to 100p
e - Period                - 10, 30 or above 60
f - Datapoints To Alarm   - Must be less than Evaluation Periods
g - Evaluation Periods    - <Period> * <Evaluation Periods> must not exceed 86400 seconds or 1 day
h - Treat Missing Data As - missing | breaching | notBreaching | ignore

Default values for this parameter is 'Average(CPUUtilization) > 90p ; 60 ; 5/5 ; missing'

.PARAMETER Dimension
Default value for this parameter is [Dimension]@{Name = 'InstanceId'; Value = '{InstanceId}'}

.PARAMETER Force
When -Force is specified, the cmdlet will proceed automatically to overwrite any existing alarm with the same name.
When -Force is not specified, and an alarm with the same name already exists,
the cmdlet will prompt for confirmation to overwrite the existing alarm,

.EXAMPLE
Get-EC2Instance -Select Reservations.Instances | New-Ec2CpuAlarm -Force -WarningAction 'Silently Continue'

This example creates/overwrite all CPU alarm on all EC2 instances,
with the default settings, and suppressing all warnings.

.EXAMPLE
New-Ec2CpuAlarm 'i-01234567890abcdef' 'Average(CPUUtilization) > 80p ; 300 ; 3/3 ; breaching'

This exmaple creates a CPU alarm on the EC2 instance 'i-01234567890abcdef'
that triggers after 3 consecutive 5-min datapoints that exceeds 80 percent.

.NOTES
General notes
#>
function New-EC2CpuAlarm
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    [Alias('alarm_ec2_cpu')]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^i-([0-9a-f]{8}|[0-9a-f]{17})$')]
        [string]
        $InstanceId,

        [ValidatePattern(
            '^(Average|Maximum|Minimum|SampleCount|Sum)\(CPUUtilization\)\s*(>|<|>=|<=)\s*(100|[1-9]?[0-9])p\s*;' +
            '\s*\d{1,}\s*;' +
            '\s*\d{1,3}\/\d{1,3}\s*;' +
            '\s*(breaching|notBreaching|ignore|missing)$'
        )]
        [string]
        $Expression = $Script:DefaultEC2CpuAlarmConfig.Expression,

        [Amazon.CloudWatch.Model.Dimension[]]
        $Dimension = $Script:DefaultEC2CpuAlarmConfig.Dimension,

        [Parameter(Position = 0)]
        [string]
        $AlarmName = $Script:DefaultEC2CpuAlarmConfig.AlarmName,

        [switch]
        $Force,

        [string[]]
        $SnsAction = @(),

        [string[]]
        $LambdaAction = @()
    )

    BEGIN
    {
        # For easy pickup.
        $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

        # Use snake_case.
        $_alarm_name    = $AlarmName
        $_expression    = $Expression
        $_sns_action    = $SnsAction
        $_lambda_action = $LambdaAction

        if ($_sns_action.Length -eq 0 -and $_lambda_action.Length -eq 0)
        {
            $_error_record = New-ErrorRecord `
                -ErrorMessage "Please provide at least one alarm action via -SnsAction or -LambdaAction parameter." `
                -ErrorId 'NoAlarmActionSpecified' `
                -ErrorCategory NotSpecified

            $PSCmdlet.ThrowTerminatingError($_error_record)
        }

        # Try to retrieve AWS Account ID & Account Name - Cannot continue if not available.
        try{
            Write-Message -Progress $_cmdlet_name 'Retrieving AWS account ID and AWS account alias.'

            if ($_alarm_name.Contains('{AccountId}'))
            {
                $_account_id = Get-STSCallerIdentity -Select Account -Verbose:$false
            }

            if ($_alarm_name.Contains('{AccountName}'))
            {
                $_account_name = (Get-IAMAccountAlias -Verbose:$false) ?? $_account_id
            }
        }
        catch
        {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Re-throw caught error.
            $PSCmdlet.ThrowTerminatingError($_)
        }

        # Split alarm expression into 4 fields.
        $_condition, [int]$_period, $_datapoints_ratio, $_treat_missing_data = $_expression -replace ' ' -split ';'

        # Extract statictic & threshold from the condition expression (first field).
        $_statistic = ($_condition -split '\(')[0]
        $_threshold = ($_condition -split '>|<|>=|<=')[1] -replace 'p' -as [int]

        # Extract comparison symbol from the condition expression (first field).
        $_comparison_symbol = $_condition -replace '[^<>=]'

        # Prepare ComparisonOperator parameter.
        $_comparison_operator = switch($_comparison_symbol){
            '>'  { [Amazon.CloudWatch.ComparisonOperator]::GreaterThanThreshold; break }
            '>=' { [Amazon.CloudWatch.ComparisonOperator]::GreaterThanOrEqualToThreshold; break }
            '<'  { [Amazon.CloudWatch.ComparisonOperator]::LessThanThreshold; break }
            '<=' { [Amazon.CloudWatch.ComparisonOperator]::LessThanOrEqualToThreshold; break }
        }

        # Extract datapoints to alarm & evaluation period from the datapoints ratio expression (third field).
        [int]$_datapoints_to_alarm, [int]$_evaluation_periods = $_datapoints_ratio -split '/'

        # Throw error if the datapoints to alarm is bigger than the evaluation periods.
        if ($_datapoints_to_alarm -gt $_evaluation_periods)
        {
            $_error_record = New-ErrorRecord `
                -ErrorMessage "Datapoints to alarm cannot be greater than evaluation periods: $($_datapoints_ratio)." `
                -ErrorId 'DatapointsToAlarmGreaterThanEvaluationPeriods' `
                -ErrorCategory InvalidArgument

            $PSCmdlet.ThrowTerminatingError($_error_record)
        }

        # Throw error if the evaluation period is more than one day.
        if ($_evaluation_periods * $_period -gt 86400)
        {
            $_error_record = New-ErrorRecord `
                -ErrorMessage "Total Evaluation period [EvaluationPeriods * Period] cannot be more than one day." `
                -ErrorId 'TotalEvaluationPeriodExceedOneDay' `
                -ErrorCategory InvalidArgument

            $PSCmdlet.ThrowTerminatingError($_error_record)
        }

        # Initialize yesToAll and noToAll ref parameters for ShouldContinue.
        $_yes_to_all = $false
        $_no_to_all  = $false
    }

    PROCESS
    {
        # Use snake_case
        $_instance_id = $InstanceId
        $_alarm_name  = $AlarmName
        $_dimension   = $Dimension
        $_force       = $Force.IsPresent

        try{
            # Abort operation if instance ID is not found.
            $_instance =  Get-EC2Instance -Verbose:$false -Select Reservations.Instances -Filter @{
                Name='instance-id'; Values=$_instance_id}
        }
        catch{
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        if (-not $_instance) {
            $PSCmdlet.WriteError("EC2 instance $_instance_id not found. Operation aborted.")
            return
        }

        # Save instance name - to use in alarm name later.
        $_instance_name = $_instance.Tags | Where-Object Key -EQ 'Name' | Select-Object -ExpandProperty Value

        # Substitute dimension values.
        $_dimension | ForEach-Object { $_.Value = $_.Value -replace '{InstanceId}', $_instance_id }

        # Figure out the name first so that we can check if the same alarm already exists.
        $_alarm_name = $_alarm_name -replace '{AccountName}', $_account_name
        $_alarm_name = $_alarm_name -replace '{AccountId}', $_account_id
        $_alarm_name = $_alarm_name -replace '{InstanceName}', $_instance_name
        $_alarm_name = $_alarm_name -replace '{InstanceId}', $_instance_id

        # Prepare parameters to create the new alarm.
        $_params = @{
            AlarmName           = $_alarm_name
            AlarmAction         = $_sns_action + $_lambda_action
            Namespace           = 'AWS/EC2'
            MetricName          = 'CPUUtilization'
            Dimension           = $_dimension
            Statistic           = $_statistic
            ComparisonOperator  = $_comparison_operator
            Threshold           = $_threshold
            DatapointsToAlarm   = $_datapoints_to_alarm
            EvaluationPeriod    = $_evaluation_periods
            Period              = $_period
            TreatMissingData    = $_treat_missing_data
            AlarmDescription    = (
                "EC2 CPU Alarm for {0}. Triggers when {1} for {2}-out-of-{3} {4} datapoints" -f `
                $_instance_name,
                $($_condition -replace '(>|<|<=|>=)(?=\d{1,})', ' ${1} '),
                $_datapoints_to_alarm,
                $_evaluation_periods,
                $($_period -lt 60 ? "$($_period)-sec" : "$($_period / 60)-min")
            )
        }

        # Prepare parameters for confirmation message.
        $_target    = "$($_alarm_name)"
        $_operation = "Creating new EC2 CPU alarm"

        # Confirmation/What-If prompt.
        if (-not $PSCmdlet.ShouldProcess($_target, $_operation)) {
            return
        }

        try{
            # Check if an alarm with the same name already exists.
            if ((Get-CWAlarm $_alarm_name -Verbose:$false | Select-Object -ExpandProperty MetricAlarms))
            {
                # Ask for confirmation to remove existing alarm.
                $_query   = "An alarm with the name `"$($_alarm_name)`" already exists. Do you want to replace it?"
                $_caption = "Remove existing alarm"

                if ($_force -or $PSCmdlet.ShouldContinue($_query, $_caption, [ref]$_yes_to_all, [ref]$_no_to_all))
                {
                    Write-Verbose '|- Removing existing alarm of the same name.'
                    Remove-CWAlarm $_alarm_name -Verbose:$false -Confirm:$false
                }
            }
            Write-CWMetricAlarm @_params -Verbose:$false

            $_format_ec2 = $_instance | Get-ResourceString `
                -IdPropertyName 'InstanceId' `
                -TagPropertyName 'Tags' `
                -StringFormat IdAndName -PlainText

            Write-Message -Output (
                "|- A new EC2 CPU alarm named `"$($_alarm_name)`" has been created for `"$($_format_ec2)`"."
            )
        }
        catch{
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating
            $PSCmdlet.WriteError($_)
        }
    }
}