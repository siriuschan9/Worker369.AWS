using namespace Amazon.EC2.Model

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

        [Parameter(ParameterSetName = 'VolumeId', Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [string]
        $VolumeId,

        [Parameter(ParameterSetName = 'VolumeName', Mandatory, Position = 0, ValueFromPipeline)]
        [string]
        $VolumeName,

        [Parameter(ParameterSetName = 'InstanceName', Mandatory, Position = 1)]
        [Parameter(ParameterSetName = 'InstanceId', Mandatory, Position = 1)]
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
        $_instance_id   = $InstanceId
        $_instance_name = $InstanceName
        $_volume_id     = $VolumeId
        $_volume_name   = $VolumeName
        $_device_name   = $DeviceName

        [string]$_mode

        switch ($_param_set)
        {
            'VolumeId' {
                $_mode                = 'volume'
                $_volume_filter_name  = 'volume-id'
                $_volume_filter_value = $_volume_id
            }
            'VolumeName' {
                $_mode                = 'volume'
                $_volume_filter_name  = 'tag:Name'
                $_volume_filter_value = $_volume_name
            }
            'InstanceId' {
                $_mode                  = 'instance'
                $_instance_filter_name  = 'instance-id'
                $_instance_filter_value = $_instance_id
            }
            'InstanceName' {
                $_mode                  = 'instance'
                $_instance_filter_name  = 'tag:Name'
                $_instance_filter_value = $_instance_name
            }
            default {
                $_error_record = New-ErrorRecord `
                    -ErrorMessage 'Unexpected Parameter Set. Operation Aborted.' `
                    -ErrorId 'UnexpectedParameterSet' `
                    -ErrorCategory NotSpecified
                $PSCmdlet.ThrowTerminatingError($_error_record)
            }
        }

        if ($_mode -eq 'volume') {
            try {
                $_ebs_list = Get-EC2Volume -Verbose -Filter @{
                    Name = $_volume_filter_name; Values = $_volume_filter_value
                }

                # If no EBS Volume matched the filter value, exit early.
                if (-not $_ebs_list) {
                    Write-Error "No EBS volume was found for '$_filter_value'."
                    return
                }

                # Loop through each EBS Volume to perform the action.
                $_ebs_list | ForEach-Object {

                    # Generate a friendly display string for the EBS Volume.
                    $_format_ebs = $_ | Get-ResourceString `
                        -IdPropertyName 'VolumeId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

                    # If volume is not attached, print error and move on to the next volume.
                    if (-not $_.Attachments) {
                        $_error_record = New-ErrorRecord `
                            -ErrorMessage "The EBS Volume `"$($_format_ebs)`" is not attached to any instances." `
                            -ErrorId 'EbsNotAttached' `
                            -ErrorCategory NotSpecified
                        $PSCmdlet.WriteError($_error_record)
                        return
                    }

                    $_.Attachments | ForEach-Object {

                        # Display What-If/Confirmation prompt.
                        if ($PSCmdlet.ShouldProcess("$_format_ebs @ $($_.InstanceId)$($_.Device)", 'Disable Delete On Termination'))
                        {
                            # Call the API to edit the EBS attribute.
                            try {
                                $_mapping                         = [InstanceBlockDeviceMappingSpecification]::new()
                                $_mapping.Ebs                     = [EbsInstanceBlockDeviceSpecification]::new()
                                $_mapping.Ebs.DeleteOnTermination = $false
                                $_mapping.DeviceName              = $_.Device

                                Edit-EC2InstanceAttribute -Verbose:$false `
                                    -InstanceId $_.InstanceId `
                                    -BlockDeviceMapping $_mapping
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
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating.
                $PSCmdlet.WriteError($_)

                # Exit early.
                return
            }
            return
        }

        if ($_mode -eq 'instance') {
            # Query the list of EC2 Instances to remove first.
            try {
                $_ec2_list = Get-EC2Instance -Verbose:$false -Filter @{
                    Name   = $_instance_filter_name
                    Values = $_instance_filter_value
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
                Write-Error "No EC2 instances was found for '$_filter_value'."
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
                        $_mapping                         = [InstanceBlockDeviceMappingSpecification]::new()
                        $_mapping.Ebs                     = [EbsInstanceBlockDeviceSpecification]::new()
                        $_mapping.Ebs.DeleteOnTermination = $false
                        $_mapping.DeviceName              = $_device_name

                        Edit-EC2InstanceAttribute -Verbose:$false `
                            -InstanceId $_.InstanceId `
                            -BlockDeviceMapping $_mapping
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
}