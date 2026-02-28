function Enable-S3Versioning
{
    [Alias('s3_ver_en')]
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
        $_region      = $Region ?? (Get-DefaultAWSRegion -Verbose:$false)

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

        # Loop through each Bucket to enable Versioning.
        $_bucket_list | ForEach-Object {

            # Display What-If/Confirmation prompt.
            if ($PSCmdlet.ShouldProcess($_.BucketArn, 'Enable Object Versioning'))
            {
                # Edit the subnet's attribute.
                try {
                    Write-S3BucketVersioning `
                        -Verbose:$false -Region $_region -VersioningConfig_Status Enabled $_.BucketName
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