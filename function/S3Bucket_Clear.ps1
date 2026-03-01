function Clear-S3Bucket
{
    [Alias('s3_clear')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]
        $BucketName
    )

    PROCESS
    {
        # Use snake_case.
        $_bucket_name = $BucketName

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
            if ($PSCmdlet.ShouldProcess($_.BucketArn, 'Empty S3 Bucket'))
            {
                $_counter = 0
                try {
                    do {
                        $_response  = Get-S3Version -Verbose:$false $_bucket_name
                        $_versions  = $_response.Versions
                        $_counter  += $_versions.Count

                        if ($_versions) {
                            Remove-S3Object -Verbose:$false -Confirm:$false -InputObject $_versions | Out-Null
                        }
                        Write-Host -NoNewline "`r"
                        Write-host -NoNewline "$($_counter) object versions deleted."
                    } while ($_response.KeyMarker)

                    Write-Host
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