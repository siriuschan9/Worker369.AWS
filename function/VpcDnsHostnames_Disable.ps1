<#
.SYNOPSIS
This cmdlet disables DNS Hostnames for one for more VPC(s).
You can specify the VPC(s) using either the -Name or -VpcId Parameter.

.PARAMETER VpcId
The -VpcId Parameter specifies the VPC ID. You can also pass in an array of VPC IDs.
This parameter supports pipeline inputs.
See example 1.

.PARAMETER VpcName
The -VpcName Parameter specifies the VPC's Name.
You can use glob wildcards to match multiple VPCs.
You can also pass in an array of Names.
See example 2.

.EXAMPLE
Disable-VpcDnsHostnames vpc-1234567890abcdef0

This example disables DNS Hostnames for the VPC vpc-1234567890abcdef0.

.EXAMPLE
Disable-VpcDnsHostnames -VpcName example-*

This example disables DNS Hostnames for all VPCs that starts with "example-".
#>
function Disable-VpcDnsHostnames
{
    [Alias('vpc_dnshost_dis')]
    [CmdletBinding(DefaultParameterSetName = 'VpcName', SupportsShouldProcess)]
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
        $_vpc_id   = $VpcId
        $_vpc_name = $VpcName

        # Configure the filter to query the VPC.
        $_filter_name  = $_param_set -eq 'VpcId' ? 'vpc-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'VpcId' ? $_vpc_id : $_vpc_name

        # Query the list of VPC first.
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

        $_vpc_list | ForEach-Object {

            # Generate a friendly display string for this VPC.
            $_format_vpc = $_ | Get-ResourceString `
                -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirmation prompt.
            if ($PSCmdlet.ShouldProcess($_format_vpc, 'Disable DNS Hostnames')) {

                # Call the API to disable the DNS hostnames for this VPC.
                try {
                    Edit-EC2VpcAttribute -EnableDnsHostname $false -Verbose:$false $_.VpcId
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