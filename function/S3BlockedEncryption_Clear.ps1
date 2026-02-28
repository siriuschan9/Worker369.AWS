function Clear-S3BlockedEncryption
{
    [Alias('s3_blkencrypt_clear')]
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
        # Use snake_case.
        $_bucket_name     = $BucketName
        $_region          = $Region ?? (Get-DefaultAWSRegion -Verbose:$false)

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

            if ($PSCmdlet.ShouldProcess($_.BucketName, 'Clear Blocked Encryption Types'))
            {
                # Get the current bucket's encryption rule.
                $_encryption_rule = `
                    Get-S3BucketEncryption -Verbose:$false -Region $_region $_.BucketName |
                    Select-Object -ExpandProperty ServerSideEncryptionRules | Select-Object -First 1

                # Clear all blocked encryption types.
                $_encryption_rule.BlockedEncryptionTypes = $null

                # Set the bucket's encryption with the modified encryption rule.
                try {
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