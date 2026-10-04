<#
.SYNOPSIS
This cmdlet starts one or more EC2 Instance(s).
You can specify the EC2 Instance(s) using either the -InstanceId or -InstanceName Parameter.

.PARAMETER InstanceId
The -InstanceId Parameter specifies the EC2 Instance ID.
You can also pass in an array of EC2 Instance IDs.
This parameter supports pipeline inputs.
See example 1.

.PARAMETER InstanceName
The -Name Parameter specifies the EC2 Instance's Name.
You can use glob wildcards to match multiple EC2 Instances.
You can also pass in an array of Names.
See example 2.

.EXAMPLE
Start-Ec2 -InstanceId i-1234567890abcdef0

This example starts the EC2 Instance i-1234567890abcdef0.

.EXAMPLE
Start-Ec2 -InstanceName example-*

This example starts all EC2 Instances with Name that starts with "example-".

#>
function Start-Ec2
{
    [Alias('ec2_start')]
    [CmdletBinding(DefaultParameterSetName = 'InstanceName', SupportsShouldProcess, ConfirmImpact = 'High')]
    param (

        [Parameter(ParameterSetName = 'InstanceId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('i-[0-9a-f]{17}', ErrorMessage = 'Invalid InstanceId.')]
        [string[]]
        $InstanceId,

        [Parameter(ParameterSetName = 'InstanceName', Mandatory, Position = 0)]
        [string[]]
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
        $_igw_name = $InstanceName
        $_igw_id   = $InstanceId

        # Configure the filter to query the EC2 Instance.
        $_filter_name  = $_param_set -eq 'InstanceId' ? 'instance-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'InstanceId' ? $_igw_id : $_igw_name

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
            Write-Error "No IGW was found for '$_filter_value'."
            return
        }

        # Loop through each EC2 Instance to perform the deletion.
        $_ec2_list | ForEach-Object {

            # Generate a friendly display string for the EC2 Instance.
            $_format_ec2 = $_ | Get-ResourceString `
                -IdPropertyName 'InstanceId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            if ($_.State.Name -eq 'pending') {
                Write-Warning "The instance $($_format_ec2) has already started."
            }

            if ($_.State.Name -eq 'running') {
                Write-Warning "The instance $($_format_ec2) is already running."
            }

            # Display What-If/Confirmation prompt.
            if ($PSCmdlet.ShouldProcess($_format_ec2, 'Start EC2 Instance'))
            {
                # Call the API to start the EC2 Instance.
                try {
                     Start-EC2Instance -Verbose:$false -Confirm:$false $_.InstanceId | Out-Null
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