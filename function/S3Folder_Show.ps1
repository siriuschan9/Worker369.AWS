
function Show-S3Folder
{
    [CmdletBinding()]
    [Alias('s3_ls')]
    param (
        [Parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [string]
        $BucketName,

        [Parameter(Position = 1, ValueFromPipeline)]
        [string]
        $Folder,

        [ValidateSet('Location', 'Type', 'StorageClass', $null)]
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

    $_dim   = [System.Management.Automation.PSStyle]::Instance.Dim
    $_reset = [System.Management.Automation.PSStyle]::Instance.Reset

    $_bucket_name      = $BucketName
    $_folder           = $Folder
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = -not $ShowRowSeparator.IsPresent

    try {
        # Download files (objects) and folders (prefixes).
        $_response = Get-S3Object -Verbose:$false -Select * `
            -BucketName $_bucket_name -Prefix $_folder -Delimiter '/'
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    if (-not $_response) { return }

    $_location = "s3://" + $_bucket_name + "/" + ($_folder -replace '[^/]+$')

    # Prepare a list to collect items in this folder.
    $_item_list = [System.Collections.Generic.List[PSObject]]::new()

    # Add folders to the list.
    foreach ($_prefix in $_response.CommonPrefixes) {

        # Extract the leaf folder => '[^/]+\/$' - Matches all characters that are not '/' to the end.
        $_name = $_prefix |
            Select-String -Pattern '[^/]+\/$' |
            Select-Object -First 1 -ExpandProperty Matches | Select-Object -ExpandProperty Value

            $_item_list.Add([PSCustomObject]@{
            Location     = $_location
            Type         = '_Folder'
            Name         = $_name
            LastModified = $null
            Size         = $null
            StorageClass = $null
        })
    }

    # Add files to the list.
    foreach ($_object in $_response.S3Objects) {

        # Extract the leaf - the file portion of the key.
        $_name = ($_object.Key -split '/')[-1]

        # Extract the extension => '(?=.)[^.]+$' - Matches all characters followed by '.' that are not '.' to the end.
        $_extension = $_name |
            Select-String -Pattern '(?=.)[^.]+$' |
            Select-Object -First 1 -ExpandProperty Matches | Select-Object -ExpandProperty Value

        $_item_list.Add([PSCustomObject]@{
            Location     = $_location
            Type         = $_extension
            Name         = $_name
            LastModified = $_object.LastModified
            Size         = $_object.Size
            StorageClass = $_object.StorageClass
        })
    }

    # We only have one default view for this cmdlet.
    $_view_definition = @{
        Default = @(
            'Type', 'StorageClass', 'LastModified', 'Size', 'Location', 'Name'
        )
    }

    # This is the definition for the -Property parameter of the Select-Object cmdlet.
    $_select_definition = @{
        LastModified = {
            $_.LastModified
        }
        Location = {
            $_.Location
        }
        Name = {
            $_.Name
        }
        Size = {
            $_.Size ? (New-ByteInfo $_.Size) : $null
        }
        StorageClass = {
            $_.StorageClass
        }
        Type = {
            $_.Type
        }
    }

    # Define a separate project definition on top of a select definition to perform some decoration on null values.
    $_project_definition = @{
        LastModified = {
            $_plain_text `
                ? $_.LastModified ?? '-'
                : $_.LastModified ?? "$_dim-$_reset"
        }
        Location = {
            $_.Location
        }
        Name = {
            $_.Name
        }
        Size = {
            $_plain_text `
                ? $_.Size ?? '-'
                : $_.Size ?? "$_dim-$_reset"
        }
        StorageClass = {
            $_plain_text `
                ? $_.StorageClass ?? '-'
                : $_.StorageClass ?? "$_dim-$_reset"
        }
        Type = {
            $_plain_text `
                ? $_.Type ?? '-'
                : $_.Type ?? "$_dim-$_reset"
        }
    }

    # Apply default sort order.
    if (
        -not $PSBoundParameters.Keys.Contains('GroupBy') -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(1, 5)      # Sort by Type, Name
    }

    # Grab the list of property names to print out.
    $_select_names = $_view_definition['Default']

    # If Group By is not in the select names, insert it to the select names.
    if (-not [string]::IsNullOrEmpty($_group_by) -and $_group_by -notin $_select_names)
    {
        $_select_names = @($_group_by) + @($_select_names)
    }

    # Exit early if there are no select names to work on
    if ($null -eq $_select_names -or $_select_names.Count -eq 0) { return }

    # Initialize a select list for Select-Object.
    $_select_list  = [System.Collections.Generic.List[object]]::new()

    # Build the select list.
    foreach ($_select_name in $_select_names)
    {
        $_select_list.Add(
            @{
                Name       = $_select_name
                Expression = $_select_definition[$_select_name] ?? {}
            }
        )
    }

    # Initialize a sort list.
    $_sort_list  = [System.Collections.Generic.List[Object]]::new()

    # Get a list of sortable names (minus the group name). The sort indexes are based on this list.
    $_sort_names = $_select_names | Where-Object { $_ -ne $_group_by }

    # Add group to sort list first. Sort by group is enforced and takes priority over caller-specified indexes.
    if(-not [string]::IsNullOrEmpty($_group_by) -and $_group_by -in $_select_names)
    {
        $_sort_list.Add(
            @{
                Expression = $_group_by;
                Descending = $false
            }
        )
    }

    # Build the sort list using the sort indexes ($_sort) and the name list ($_sort_names).
    for($_i = 0 ; $_i -lt $_sort.Length ; $_i++)
    {
        # Column number is 1-based. Column index is 0-based.
        $_sort_index = [Math]::Abs($_sort[$_i]) - 1

        # Guard against index out of bound.
        if ($_sort_index -ge $_sort_names.Length) { continue }

        # Get the column name.
        $_sort_name = $_sort_names[$_sort_index]

        # Get ascending or descending.
        $_descending = $($_sort[$_i] -lt 0)

        $_sort_list.Add(
            @{
                Expression = "$_sort_name"
                Descending = $_descending
            }
        )
    }

    # Initialize a project list.
    $_project_list  = [System.Collections.Generic.List[Object]]::new()

    # Get a list of projectable names (minus the group name). The exclude indexes are based on this list.
    $_project_names = $_select_names.Where({$_ -notin $_group_by})

    # Add the group property to the project list first.
    if (-not [string]::IsNullOrEmpty($_group_by) -and $_group_by -in $_select_names)
    {
        $_project_list.Add($_group_by)
    }

    # Add all properties not in the exclude list to the project list.
    for ($_i = 0 ; $_i -lt $_project_names.Count; $_i++)
    {
        if (($_i + 1) -notin $_exclude)
        {
            $_project_name = $_project_names[$_i].psobject.BaseObject
            $_project_list.Add(
                @{
                    Name       = [string]$_project_name
                    Expression = $_project_definition[$_project_name] ?? {}
                }
            )
        }
    }

    # Generate output after sorting and exclusion.
    $_output = $_item_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -GroupBy $_group_by -AlignRight LastModified, Size `
            -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}