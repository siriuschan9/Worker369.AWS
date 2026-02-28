<#
.SYNOPSIS
The cmdlet creates an VPC Block Public Access Exclusion for each specifed VPC.
You can specify the VPC(s) using either the -VpcName or -VpcId Parameter.

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

.PARAMETER ExclusionMode
The -ExclusionMode Parameter specifies the exclusion mode.
Valid values for this parameter are "allow-bidirectional", "allow-egress".
The "allow-egress" exception is valid only when then the block mode is set to "block-bidirectional".

.EXAMPLE
New-VpcBpaExclusion -ExclusionMode allow-egress vpc-12345678901234567

This example creates an "allow-egress" exclusion for vpc-12345678901234567.

.EXAMPLE
New-VpcBpaExclusion -ExclusionMode allow-bidirectional -VpcName example-2

This example creates an "allow-bidirectional" exclusion for the VPC named "example-2".
#>
function New-VpcBpaExclusion
{
    [Alias('vpc_bpa_excl_add')]
    [CmdletBinding(DefaultParameterSetName = 'VpcName', SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = 'VpcId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]
        $VpcId,

        [Parameter(ParameterSetName = 'VpcName', Mandatory, Position = 0)]
        [string[]]
        $VpcName,

        [Parameter(Mandatory)]
        [Amazon.EC2.InternetGatewayExclusionMode]
        $ExclusionMode
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_vpc_id    = $VpcId
        $_vpc_name  = $VpcName
        $_excl_mode = $ExclusionMode

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

        # Loop through each VPC to perform the exclusion.
        $_vpc_list | ForEach-Object {

            # Generate a friendly display string for this VPC.
            $_format_vpc = $_ | Get-ResourceString `
                -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirm prompt.
            if ($PSCmdlet.ShouldProcess($_format_vpc, "Create New VPC Block Public Access $($_excl_mode) Exclusion"))
            {
                try {
                    $_excl = New-EC2VpcBlockPublicAccessExclusion `
                        -VpcId $_.VpcId `
                        -InternetGatewayExclusionMode $_excl_mode `
                        -Verbose:$false

                    Write-Message -Output "|- ExclusionId: $($_excl.ExclusionId)"
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