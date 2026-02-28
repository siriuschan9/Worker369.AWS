function Set-S3Encryption
{
    [Alias('s3_encrypt')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Position = 0, Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]
        $BucketName,

        [object]
        $Region,

        [Parameter(Position = 1)]
        [ValidateSet('SSE-S3', 'SSE-KMS', 'DSSE-KMS')]
        [string]
        $EncryptionType,

        [Parameter(Position = 2)]
        [string]
        $KmsKeyArn
    )

    PROCESS
    {
        # Use snake_case.
        $_bucket_name     = $BucketName
        $_region          = $Region ?? (Get-DefaultAWSRegion -Verbose:$false)
        $_encryption_type = $EncryptionType
        $_kms_key_arn     = $KmsKeyArn

        if ($_encryption_type -in @('SSE-KMS', 'DSSE-KMS') -and [string]::IsNullOrEmpty($_kms_key_arn)) {

            $_error = New-ErrorRecord `
                -ErrorMessage 'KmsKeyArn is required when EncryptionType one of the following: SSE-KMS, DSSE-KMS.' `
                -ErrorId 'MissingKmsKeyArn' `
                -ErrorCategory InvalidArgument

                $PSCmdlet.ThrowTerminatingError($_error)
        }

        if ($_encryption_type -eq 'SSE-S3' -and -not [string]::IsNullOrEmpty($_kms_key_arn)) {
            $PSCmdlet.WriteWarning(
                'KmsKeyArn is not required when EncryptionType is SSE-S3. It will be ignored.'
            )
            $_kms_key_arn = $null
        }

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

            if ($PSCmdlet.ShouldProcess($_.BucketArn, 'Set Bucket Encryption'))
            {
                # Create a default encryption object.
                $_default_encryption = [Amazon.S3.Model.ServerSideEncryptionByDefault]@{
                    ServerSideEncryptionAlgorithm = $_server_side_encryption_method
                }

                # Set the KMS key ARN on the default encryption object.
                $_default_encryption.ServerSideEncryptionAlgorithm = `
                    switch ($_encryption_type)
                    {
                        'SSE-S3'   { 'AES256' }
                        'SSE-KMS'  { 'aws:kms' }
                        'DSSE-KMS' { 'aws:kms:dsse' }
                        default    { throw "Unhandled encryption type: $($_encryption_type)" }
                    }

                # Set the KMS key ARN on the default encryption object.
                if ($_encryption_type -in @('SSE-KMS', 'DSSE-KMS')) {
                    $_default_encryption.ServerSideEncryptionKeyManagementServiceKeyId = $_kms_key_arn
                }

                # Get the current bucket's encryption rule.
                $_encryption_rule = `
                    Get-S3BucketEncryption -Verbose:$false -Region $_region $_.BucketName |
                    Select-Object -ExpandProperty ServerSideEncryptionRules | Select-Object -First 1

                # Assign the default encryption object to the encryption rule.
                $_encryption_rule.ServerSideEncryptionByDefault = $_default_encryption

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