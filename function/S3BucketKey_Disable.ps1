function Disable-S3BucketKey
{
    [Alias('s3_bkey_dis')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Position = 0, Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
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

        # Loop through each Bucket to configure encryption settings.
        $_bucket_list | ForEach-Object {

            # Display What-If/Confirmation prompt.
            if ($PSCmdlet.ShouldProcess($_.BucketArn, 'Disable S3 Bucket Key'))
            {
                try {
                    # Get the current bucket's encryption rule.
                    $_encryption_rule = `
                        Get-S3BucketEncryption -Verbose:$false $_.BucketName |
                        Select-Object -ExpandProperty ServerSideEncryptionRules | Select-Object -First 1

                    # Disable bucket key on the encryption rule.
                    $_encryption_rule.BucketKeyEnabled = $false

                    # Set the bucket's encryption with the modified encryption rule.
                    Set-S3BucketEncryption -Verbose:$false -Region $_region $_.BucketName `
                        -ServerSideEncryptionConfiguration_ServerSideEncryptionRule $_encryption_rule `
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