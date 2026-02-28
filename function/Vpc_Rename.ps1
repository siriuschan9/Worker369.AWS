<#
.SYNOPSIS
This cmdlet renames a VPC.

.PARAMETER VpcId
The -VpcId Parameter specifies the VPC ID.
This parameter supports pipeline inputs.
See example 1

.PARAMETER VpcName
The -VpcName Parameter specifies the VPC's Name.
You can use glob wildcards to match multiple VPCs.
See example 2.

.PARAMETER NewName
The -NewName Parameter specifies the new Name.

.EXAMPLE
Rename-Vpc vpc-12345678901234560 example-1-new

This example renames the VPC vpc-12345678901234560 to "example-1-new".

.EXAMPLE
Rename-Subnet -VpcName example-2 -NewName example-2-new

This example renames the Subnet(s) named "example-2" to "example-2-new".
#>
function Rename-Vpc
{
    [Alias('vpc_rn')]
    [CmdletBinding(DefaultParameterSetName = 'VpcName', SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = 'VpcId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^vpc-[0-9a-f]{17}$', ErrorMessage = 'Invalid VpcId.')]
        [string]
        $VpcId,

        [Parameter(ParameterSetName = 'VpcName', Mandatory, Position = 0)]
        [string]
        $VpcName,

        [Parameter(Mandatory, Position = 1)]
        [string]
        $NewName
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_vpc_id   = $VpcId
        $_vpc_name = $VpcName
        $_new_name = $NewName

        # Configure the filter to query the Subnet.
        $_filter_name  = $_param_set -eq 'VpcId' ? 'vpc-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'VpcId' ? $_vpc_id : $_vpc_name

        # Query the list of Subnet to rename first.
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

        # Loop through each VPC to perform the renaming.
        $_vpc_list | ForEach-Object {

            # Generate a friendly display string for the VPC.
            $_format_vpc = $_ | Get-ResourceString `
                -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirm prompt.
            if ($PSCmdlet.ShouldProcess($_format_vpc, "Rename VPC"))
            {
                # Call the API to revalue the Name Tag.
                try {
                    New-EC2Tag -Verbose:$false -Resource $_.VpcId -Tag @{Key = 'Name'; Value = $_new_name}
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