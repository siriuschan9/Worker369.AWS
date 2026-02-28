function Show-S3FileVersion
{
    [Alias('s3_ver')]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory)]
        [string]
        $BucketName,

        [Parameter(Position = 1)]
        [string]
        $Folder,

        [ValidateSet('Location')]
        [string]
        $GroupBy = 'Location',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $ShowRowSeparator
    )

    $_bucket_name      = $BucketName
    $_folder           = $Folder
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = -not $ShowRowSeparator.IsPresent

    try {
        $_version_list = `
            Get-S3Version -Verbose:$false -Select * -BucketName $_bucket_name -Prefix $_folder -Delimiter '/' |
            Select-Object -ExpandProperty Versions
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    if (-not $_version_list) { return }

    # Save a reference to the normalized folder.
    $_location = "s3://" + $_bucket_name + "/" + ($_folder -replace '[^/]+$')

    $_view_definition = @{
        Default = @(
            'StorageClass', 'IsLatest', 'IsDeleteMarker', 'LastModified', 'Size', 'Name', 'VersionId'
        )
    }

    $_select_definition = @{
        IsDeleteMarker = {
            New-Checkbox -PlainText:$_plain_text ($_.IsDeleteMarker ?? $false)
        }
        IsLatest = {
            New-Checkbox -PlainText:$_plain_text $_.IsLatest
        }
        LastModified = {
            $_.LastModified
        }
        Location = {
            $_location
        }
        Name = {
            ($_.Key -split '/')[-1]
        }
        Size = {
            New-ByteInfo $_.Size
        }
        StorageClass = {
            $_.StorageClass
        }
        Uri = {
            "s3://$($_.BucketName)/$($_.Key)"
        }
        VersionId = {
            $_.VersionId
        }
    }

    # Apply default sort order.
    if (
        -not $PSBoundParameters.Keys.Contains('GroupBy') -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(6, -4) # Sort by Name, LastModified
    }

    $_view = 'Default'

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Generate output after sorting and exclusion.
    $_output = $_version_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -GroupBy $_group_by `
            -AlignLeft IsLatest, IsDeleteMarker `
            -PlainText:$_plain_text `
            -NoRowSeparator:$_no_row_separator
    }
}