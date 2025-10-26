function Remove-VpcBpaExclusion
{
    [Alias('vpc_bpa_excl_rm')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^vpcbpa-exclude-[0-9a-f]{17}$', ErrorMessage = 'Invalid Exclusion ID.')]
        [string[]]
        $ExclusionId
    )

    PROCESS
    {
        # Use snake_case.
        $_excl_id = $ExclusionId

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
            Write-Error "No Exclusion ID was found for '$_excl_id'."
            return
        }

        # Loop through each exclusion to perform the deletion.
        $_excl_list | ForEach-Object {

            $_excl = $_

            if ($PSCmdlet.ShouldProcess(
                "ExclusionId: $($_excl.ExclusionId) | " +
                "VpcId: $($_excl.ResourceArn -replace '^arn:aws:ec2:[0-9a-z-]+:\d{12}:vpc\/')",
                "Remove VPC Block Public Access Exclusion")) {

                try {
                    $_response = Remove-EC2VpcBlockPublicAccessExclusion $_excl.ExclusionId `
                        -Verbose:$false -Confirm:$false

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

# [Amazon.EC2.VpcBlockPublicAccessExclusionState].GetFields() | ForEach-Object {
#   $_.GetValue($null).Value
# }
# create-complete | create-failed | create-in-progress | delete-complete | delete-in-progress |
# disable-complete | disable-in-progress | update-complete | update-failed | update-in-progress