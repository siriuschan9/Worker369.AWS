<#
.SYNOPSIS
This cmdlet removes one or more VPC(s).
You can specify the VPC(s) using either the -Name or -VpcId Parameter.

.PARAMETER VpcId
The -VpcId Parameter specifies the VPC ID.
You can also pass in an array of VPC IDs.
This parameter supports pipeline inputs.
See example 1.

.PARAMETER VpcName
The -VpcName Parameter specifies the VPC's Name.
You can use glob wildcards to match multiple VPCs.
You can also pass in an array of Names.
See example 2.

.EXAMPLE
Remove-Vpc -VpcId vpc-1234567890abcdef0

This example removes the VPC vpc-1234567890abcdef0.

.EXAMPLE
Remove-Vpc -VpcName example-*

This example removes all VPCs with Name that starts with "example-".
#>
function Remove-Vpc
{
    [Alias('vpc_rm')]
    [CmdletBinding(DefaultParameterSetName = 'VpcName', SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ParameterSetName = 'VpcId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^vpc-[0-9a-f]{17}$', ErrorMessage = 'Invalid VpcId.')]
        [string[]]
        $VpcId,

        [Parameter(ParameterSetName = 'VpcName', Mandatory, Position = 0)]
        [string[]]
        $VpcName
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_vpc_name = $VpcName
        $_vpc_id   = $VpcId

        # Configure the filter to query the VPC.
        $_filter_name  = $_param_set -eq 'VpcId' ? 'vpc-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'VpcId' ? $_vpc_id : $_vpc_name

        # Query the list of VPC to remove first.
        try {
            $_vpc_list = Get-EC2Vpc -Verbose:$false -Filter @{Name = $_filter_name; Values = $_filter_value}
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no VPC matched the filter value, exit early.
        if (-not $_vpc_list)
        {
            Write-Error "No VPC was found for '$_filter_value'."
            return
        }

        # Loop through each VPC to perform the deletion.
        $_vpc_list | ForEach-Object {

            # Generate a friendly display string for the VPC.
            $_format_vpc = $_ | Get-ResourceString `
                -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirm prompt.
            if ($PSCmdlet.ShouldProcess($_format_vpc, "Remove VPC"))
            {
                # Call the API to remove the VPC.
                try {
                    Remove-EC2Vpc -Verbose:$false -Confirm:$false $_.VpcId
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