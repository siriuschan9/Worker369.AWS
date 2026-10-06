function Invoke-SsmPowerShellCommand
{
    [CmdletBinding(DefaultParameterSetName = 'SpecificTargets',SupportsShouldProcess, ConfirmImpact = 'High')]
    [Alias('ssm_pwsh')]
    param (
        [Parameter(
            ParameterSetName = 'SpecificTargets', Mandatory, Position = 0,
            ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]
        $InstanceId,

        [Parameter(ParameterSetName = 'SpecificPlatforms')]
        [ValidateSet('Windows', 'Linux')]
        [string[]]
        $PlatformType,

        [Parameter(Mandatory, Position = 1)]
        [string[]]
        $Command,

        [Parameter()]
        [ValidateRange(3, 172800)]
        [int]
        $ExecutionTimeout = 3600,

        [ValidateLength(0, 4096)]
        [string]
        $WorkingDirectory,

        [ValidateRange(30, 2592000)]
        [int]
        $DeliveryTimeout = 600
    )

    BEGIN
    {
        # For easy pick-up later.
        $_param_set = $PSCmdlet.ParameterSetName

        # Initialize a Instance ID list to collect all Instance ID streamed from the pipeline.
        $_instance_id_list = [System.Collections.Generic.List[string]]::new()
    }

    PROCESS
    {
        if ($_param_set -eq 'SpecificTargets') {
            $_instance_id_list.AddRange($InstanceId -as [string[]])
        }
    }

    END
    {
        $_platform_type_list = $PlatformType
        $_command            = $Command
        $_execution_timeout  = $TimeoutSeconds
        $_working_directory  = $WorkingDirectory
        $_delivery_timeout   = $DeliveryTimeout

        try {

            # If -All parameter is specified, fetch all Linux and MacOS instances.
            if ($_param_set -eq 'SpecificPlatforms') {
                $_instance_id_list = Get-SSMInstanceInformation -Verbose:$false -Filter @{
                    Key    = 'PlatformTypes'
                    Values = $_platform_type_list
                } | Select-Object -ExpandProperty InstanceId
            }

            # If there are no available instances, exit early.
            if (-not $_instance_id_list) {
                Write-Warning 'No instances are in the available state to run the command(s).'
                return
            }

            if (-not $PSCmdlet.ShouldProcess(
                "Performing the operation `"Run Shell Script`" on $($_instance_id_list.Count) instance(s).",
                $null, $null)) {
                return
            }

            # Prepare parameters for AWS-RunShellScript document.
            $_parameters = @{commands = $_command}
            if ($PSBoundParameters.ContainsKey('WorkinDirectory')) {
                $_parameters.Add('workingDirectory', $_working_directory)
            }
            if ($PSBoundParameters.ContainsKey('ExecutionTimeout')) {
                $_parameters.Add('executionTimeout', $_execution_timeout)
            }

            $_response = Send-SSMCommand -Verbose:$false `
                -Target @{Key = 'InstanceIds'; Values = $_instance_id_list} `
                -DocumentName 'AWS-RunShellScript' `
                -TimeoutSecond $_delivery_timeout `
                -Parameter $_parameters
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Re-throw caught exception.
            $PSCmdlet.ThrowTerminatingError($_)
        }
        $_response | Select-Object CommandId
    }
}

# InstanceId
Register-ArgumentCompleter -ParameterName 'InstanceId' -CommandName 'Invoke-SsmPowerShellCommand' -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_instance_list = Get-SSMInstanceInformation -Verbose:$false -Filter @{
        Key    = 'PlatformTypes'
        Values = @('Linux', 'Windows')
    } | Where-Object { $_.InstanceId -like "$_word_to_complete*" }

    if (-not $_instance_list) { return }

    $_align = `
        $_instance_list.InstanceId | Select-Object -ExpandProperty Length |
        Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_instance_list | Get-HintItem -IdPropertyName 'InstanceId' -NamePropertyName 'ComputerName' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}