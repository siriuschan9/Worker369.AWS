function Show-S3Policy
{
    [Alias('s3_policy_show')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]
        $BucketName,

        [object]
        $Region
    )

    PROCESS
    {
        # Use snake_case
        $_bucket_name = $BucketName
        $_region      = $Region ?? (Get-DefaultAWSRegion).Region

        # Query the list of Bucket first.
        try {
            $_bucket_list = ($_bucket_name.Contains('*') -or $_bucket_name.Contains('?')) `
                ? (Get-S3Bucket -Verbose:$false -Region $_region | Where-Object BucketName -Like $_bucket_name) `
                : (Get-S3Bucket -Verbose:$false -Region $_region $_bucket_name)
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If there are no Bucket returned, exit early.
        if (-not $_bucket_list)
        {
            Write-Error "No Bucket was found for '$_bucket_name'."
            return
        }

        $_bucket_list | ForEach-Object {

            try {
                $_policy = Get-S3BucketPolicy -Verbose:$false -Region $_.BucketRegion $_.BucketName
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating.
                $PSCmdlet.WriteError($_)
            }

            if ($_policy | Test-Json -ErrorAction SilentlyContinue) {
                $_policy | Format-Json
            }
        }
    }
}