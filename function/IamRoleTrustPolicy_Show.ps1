function Show-IamRoleTrustPolicy
{
    [Alias('role_trust_show')]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]
        $RoleName
    )

    PROCESS
    {
        # Use snake_case
        $_role_name = $RoleName

        try {
            $_trust = Get-IAMRole -Verbose:$false $_role_name | Select-Object -ExpandProperty AssumeRolePolicyDocument
            [System.Web.HttpUtility]::UrlDecode($_trust) | Format-Json
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }
    }
}