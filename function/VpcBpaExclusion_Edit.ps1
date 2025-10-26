function Edit-VpcBpaExclusion
{
    [Alias('vpc_bpa_excl_edit')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^vpcbpa-exclude-[0-9a-f]{17}$', ErrorMessage = 'Invalid Exclusion ID.')]
        [string[]]
        $ExclusionId,

        [Parameter(Mandatory)]
        [Amazon.EC2.InternetGatewayExclusionMode]
        $ExclusionMode
    )

    PROCESS
    {
        # Use snake_case.
        $_excl_id   = $ExclusionId
        $_excl_mode = $ExclusionMode

        # Query the list of exclusion first.
        try {
            $_excl_list = Get-EC2VpcBlockPublicAccessExclusion -Verbose:$false -ExclusionId $_excl_id
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no exclusion ID matched the filter, exit early.
        if (-not $_excl_list)
        {
            Write-Error "No Exclusion ID was found for `$_excl_id`."
            return
        }

        $_excl_list | ForEach-Object {

            # Display What-If/Confirm prompt.
            if ($PSCmdlet.ShouldProcess(
                "ExclusionId: $($_excl.ExclusionId) | “ +
                ”VPCId: $($_excl.ResourceArn -replace '^arn:aws:ec2:[0-9a-z-]+:\d{12}:vpc\/')",
                "Edit VPC Block Public Access Exclusion")) {

                try {
                    $_response = Edit-EC2VpcBlockPublicAccessExclusion $_.ExclusionId `
                        -InternetGatewayExclusionMode $_excl_mode `
                        -Verbose:$false

                    Write-Message -Output "|- Status: $($_response.State)"
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