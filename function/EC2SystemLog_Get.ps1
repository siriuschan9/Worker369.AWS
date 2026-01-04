function Get-EC2SystemLog
{
    [CmdletBinding(DefaultParameterSetName = 'InstanceName')]
    [Alias('ec2_console')]
    param (
        [Parameter(ParameterSetName = 'InstanceId', Mandatory, ValueFromPipelineByPropertyName, ValueFromPipeline)]
        [ValidatePattern('^i-([0-9a-f]{8}|[0-9a-f]{17})$')]
        [string]
        $InstanceId,

        [Parameter(ParameterSetName = 'InstanceName', Mandatory, Position = 0)]
        [string]
        $InstanceName
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }
    PROCESS
    {
        # Use snake_case.
        $_instance_id   = $InstanceId
        $_instance_name = $InstanceName

        # Configure the filter to query the Network ACL.
        $_filter_name  = $_param_set -eq 'InstanceId' ? 'instance-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'InstanceId' ? $_instance_id : $_instance_name

        $_filter = [Amazon.EC2.Model.Filter]@{
            Name   = $_filter_name
            Values = $_filter_value
        }

        # Query the list of Instance ID first.
        try {
            $_instance_list = Get-EC2Instance -Verbose:$false -Filter $_filter | Select-Object -ExpandProperty Instances
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no instances matched the filter value, exit early.
        if (-not $_instance_list) {
            Write-Error "No instances were found for '$_filter_value'."
            return
        }

        $_instance_list | ForEach-Object {

            try{
                $_encoded = $_.InstanceId | Get-EC2ConsoleOutput | Select-Object -ExpandProperty Output
                [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_encoded))
            }
            catch{
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating.
                $PSCmdlet.WriteError($_)
            }
        }
    }
}