function Invoke-SsmShellCommand
{
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [Alias('ssm_sh')]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]
        $InstanceId,

        [Parameter(Mandatory, Position = 1)]
        [string[]]
        $Command,

        [int]
        [ValidateRange(3, 172800)]
        $TimeoutSeconds = 3600
    )

    BEGIN
    {
        $_instance_id_list = [System.Collections.Generic.List[string]]::new()
    }

    PROCESS
    {
        $_instance_id_list.AddRange($InstanceId -as [string[]])
    }

    END
    {
        $_command = $Command
        $_timeout = $TimeoutSeconds

        try {

            if (-not $PSCmdlet.ShouldProcess("$($_instance_id_list.Count) Instances.", 'Run Shell Commands')) {
                return
            }

            $_response = Send-SSMCommand -Verbose:$false `
                -DocumentName 'AWS-RunShellScript' `
                -TimeoutSecond $_timeout `
                -Parameter @{commands = $_command}
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
Register-ArgumentCompleter -ParameterName 'InstanceId' -CommandName 'Invoke-SsmShellCommand' -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_instance_list = Get-SSMInstanceInformation -Verbose:$false -Filter @{
        Key   = 'PlatformTypes'
        Values = "Linux"
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