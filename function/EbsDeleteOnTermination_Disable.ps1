function Disable-EbsDeleteOnTermination
{
    [Alias('ebs_dot_dis')]
    [CmdletBinding(DefaultParameterSetName = 'InstanceName', SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ParameterSetName = 'InstanceId',Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [ValidatePattern('i-[0-9a-f]{17}', ErrorMessage = 'Invalid InstanceId.')]
        [string]
        $InstanceId,

        [Parameter(ParameterSetName = 'InstanceName', Mandatory, Position = 0)]
        [string]
        $InstanceName,

        [ValidatePattern]
        [string]
        $DeviceName
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_ec2_name    = $InstanceName
        $_ec2_id      = $InstanceId
        $_device_name = $DeviceName

        # Configure the filter to query the EC2 Instance.
        $_filter_name  = $_param_set -eq 'InstanceId' ? 'instance-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'InstanceId' ? $_ec2_id : $_ec2_name

        # Query the list of EC2 Instances to remove first.
        try {
            $_ec2_list = Get-EC2Instance -Verbose:$false -Filter @{
                Name   = $_filter_name
                Values = $_filter_value
            } | Select-Object -ExpandProperty Instances
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no EC2 Instance matched the filter value, exit early.
        if (-not $_ec2_list)
        {
            Write-Error "No ec2 was found for '$_filter_value'."
            return
        }

        # Loop through each EC2 Instance to perform the action.
        $_ec2_list | ForEach-Object {

            # Generate a friendly display string for the EC2 Instance.
            $_format_ec2 = $_ | Get-ResourceString `
                -IdPropertyName 'InstanceId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirmation prompt.
            if ($PSCmdlet.ShouldProcess("Device $($_device_name) of $_format_ec2", 'Disable Delete On Termination'))
            {
                # Call the API to start the EC2 Instance.
                try {
                    $_mapping = [Amazon.EC2.Model.InstanceBlockDeviceMappingSpecification]::new()
                    $_mapping.DeviceName = $_device_name
                    $_mapping.Ebs = [Amazon.EC2.Model.EbsInstanceBlockDeviceSpecification]::new()
                    $_mapping.ebs.DeleteOnTermination = $false
                    Edit-EC2InstanceAttribute -Verbose:$false -InstanceId $_.InstanceId -BlockDeviceMapping $_mapping
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