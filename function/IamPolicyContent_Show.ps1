function Show-IamPolicyContent
{
    [Alias('iam_policy_cat')]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory)]
        [string]
        $PolicyArn,

        [Parameter()]
        [string]
        $VersionId
    )

    PROCESS
    {
        # Use snake case.
        $_policy_arn = $PolicyArn
        $_version_id = $VersionId

        if (-not $_version_id)
        {
            try {
                $_version_id = (Get-IAMPolicy -Verbose:$false $_policy_arn).DefaultVersionId
            }
            catch {
                # Remove caught excetion emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating.
                $PSCmdlet.WriteError($_)
            }
        }

        try {
            $_document = (Get-IAMPolicyVersion -Verbose:$false -VersionId $_version_id $_policy_arn).Document
            [System.Web.HttpUtility]::UrlDecode($_document) | Format-Json
        }
        catch {
            # Remove caught excetion emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit this PROCESS block early.
            return
        }
    }
}