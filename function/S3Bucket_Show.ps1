<#
.SYNOPSIS
This cmdlet prints out a listing of S3 Bucket.

.PARAMETER BucketName
By default, this cmdlet prints out all S3 Buckets.
The -BucketName Parameter specifies an optional filter on the Bucket Name.
You can use glob wildcard such as * or ?.
See example 2.

.PARAMETER Region
By default, this cmdlet prints out all S3 Buckets.
The -Region Parameter specifies an optional filter on the Bucket Region.
You can use glob wildcard such as * or ?.
See example 3.

.EXAMPLE
Show-S3Bucket -View Encryption

This example prints out a listing of S3 Buckets with columns related to Bucket encryption settings.

.EXAMPLE
Show-S3Bucket -BucketName example-*

This example prints out all S3 Buckets that starts with example-.

.EXAMPLE
Show-S3Bucket -Region ap-southeast-1

This example prints out all S3 Buckets in ap-southeast-1 region only.
#>
function Show-S3Bucket
{
    [Alias('s3_show')]
    [CmdletBinding()]
    param (
        [string]
        $BucketName,

        [object]
        $Region,

        [parameter(Position = 0)]
        [ValidateSet('Metrics', 'Versioning', 'Encryption', 'Permission')]
        [string]
        $View = 'Metrics',

        [ValidateSet('BucketRegion', $null)]
        [string]
        $GroupBy = 'BucketRegion',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # For easy pick up later.
    $script:_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name
    $_dim                = [System.Management.Automation.PSStyle]::Instance.Dim
    $_reset              = [System.Management.Automation.PSStyle]::Instance.Reset

    # Use snake_case
    $_bucket_name      = $BucketName
    $_region           = $Region
    $_view             = $View
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_select_definition = @{
        BlockedEncryption = {
            $_encryption_rule = $_encryption_lookup[$_.BucketName]
            $_blocked = $_encryption_rule.BlockedEncryptionTypes.EncryptionType -join ','
            $_blocked = [string]::IsNullOrEmpty($_blocked) `
                ? ($_plain_text ? '-' : "$($_dim)-$($_reset)")
                : $_blocked
            $_blocked
        }
        BlockPublicAcls = {
            $_block_public_acls = $_bpa_lookup[$_.BucketName].BlockPublicAcls ?? $false
            New-Checkbox -PlainText:$_plain_text $_block_public_acls
        }
        BlockPublicPolicy = {
            $_block_public_policy = $_bpa_lookup[$_.BucketName].BlockPublicPolicy ?? $false
            New-Checkbox -PlainText:$_plain_text $_block_public_policy
        }
        BucketName = {
            $_.BucketName
        }
        BucketRegion = {
            $_.BucketRegion
        }
        BucketSize = {
            $_bucket_size_lookup[$_.BucketName] ?? (New-ByteInfo 0)
        }
        CreationDate = {
            $_.CreationDate
        }
        EnableMfaDelete = {
            $_enabled = $_versioning_lookup[$_.BucketName].EnableMfaDelete ?? $false
            New-Checkbox -PlainText:$_plain_text $_enabled
        }
        EncryptionType = {
            $_encryption_rule = $_encryption_lookup[$_.BucketName]
            $_encryption_algo = $_encryption_rule.ServerSideEncryptionByDefault.ServerSideEncryptionAlgorithm
            switch ($_encryption_algo)
            {
                'AES256'       { 'SSE-S3' }
                'aws:kms'      { 'SSE-KMS' }
                'aws:kms:dsse' { 'DSSE-KMS' }
                default        { $_encryption_algo}
            }
        }
        EncryptionKey = {
            $_encryption_rule = $_encryption_lookup[$_.BucketName]

            $_encryption_rule.ServerSideEncryptionByDefault.ServerSideEncryptionKeyManagementServiceKeyId `
                ?? ($_plain_text ? '-' : "$($_dim)-$($_reset)")
        }
        HasBucketPolicy = {
            New-Checkbox -PlainText:$_plain_text ($_has_bucket_policy_lookup[$_.BucketName] ?? $false)
        }
        HasLifecycleRules = {
            New-Checkbox -PlainText:$_plain_text ($_has_lifecycle_lookup[$_.BucketName] ?? $false)
        }
        IgnorePublicAcls = {
            $_ignore_public_acls = $_bpa_lookup[$_.BucketName].IgnorePublicAcls ?? $false
            New-Checkbox -PlainText:$_plain_text $_ignore_public_acls
        }
        NumObjects = {
            $_num_objects_lookup[$_.BucketName] ?? (New-NumberInfo 0)
        }
        RestrictPublicBuckets = {
            $_restrict_public_buckets = $_bpa_lookup[$_.BucketName].RestrictPublicBuckets ?? $false
            New-Checkbox -PlainText:$_plain_text $_restrict_public_buckets
        }
        UseBucketKey = {
            $_use_bucket_key = $_encryption_lookup[$_.BucketName] | Select-Object -ExpandProperty BucketKeyEnabled
            New-Checkbox -PlainText:$_plain_text $_use_bucket_key
        }
        VersioningStatus = {
            $_status = $_versioning_lookup[$_.BucketName].Status
            $_enabled = $_status -eq 'Enabled'

            New-Checkbox -PlainText:$_plain_text -Description $_status $_enabled
        }
    }

    $_view_definition = @{
        Encryption = (
            'BucketName', 'BucketRegion', 'EncryptionType', 'UseBucketKey', 'EncryptionKey', 'BlockedEncryption'
        )
        Metrics = @(
            'BucketName', 'BucketRegion', 'CreationDate', 'NumObjects', 'BucketSize'
        )
        Permission = (
            'BucketName', 'BlockPublicAcls',  'IgnorePublicAcls', 'BlockPublicPolicy', 'RestrictPublicBuckets',
            'HasBucketPolicy'
        )
        Versioning = @(
            'BucketName', 'BucketRegion', 'VersioningStatus', 'EnableMfaDelete', 'HasLifecycleRules'
        )
    }

    # Apply default sort order.
    if (
        $_view -eq 'Metrics' -and
        $_group_by -eq 'BucketRegion' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(1) # => Sort by BucketName
    }

    # Display a dimmed dash for zero - used for Default view.
    $_counter_style = [Worker369.Utility.NumberInfoSettings]::Make()
    $_counter_style.Format.Unscaled = "#,###;#,###;`e[2m-`e[0m"

    # Display an unstyled dash for zero - used for Default view.
    $_counter_plain = [Worker369.Utility.NumberInfoSettings]::Make()
    $_counter_plain.Format.Unscaled = '#,###;#,###;-'

    # Get all buckets.
    try {
        $_bucket_list = Get-S3Bucket -Verbose:$false

        if (-not [string]::IsNullOrEmpty($_bucket_name)) {
            $_bucket_list = $_bucket_list | Where-Object BucketName -like $_bucket_name
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Get bucket regions.
    Write-BucketRegion $_bucket_list

    # Filter bucket by region if -Region parameter is specified
    if ($_region) {
        $_bucket_list = $_bucket_list | Where-Object BucketRegion -like $_region
    }

    # Exit early if there are no buckets to show.
    if (-not $_bucket_list) {
        return
    }

    # Get bucket encryption.
    if ($_view -in @('Encryption')) {
        $_encryption_lookup = Get-BucketEncryption $_bucket_list
    }

    # Get bucket metrics.
    if ($_view -in @('Metrics')) {
        $_bucket_size_lookup, $_num_objects_lookup = Get-BucketMetric $_bucket_list
    }

    # Get bucket permission.
    if ($_view -in @('Permission')) {
        $_bpa_lookup, $_has_bucket_policy_lookup = Get-BucketPermission $_bucket_list
    }

    # Get bucket versioning.
    if ($_view -in @('Versioning')) {
        $_versioning_lookup, $_has_lifecycle_lookup = Get-BucketVersioning $_bucket_list
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Generate output after sorting and exclusion.
    $_output = $_bucket_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -GroupBy $_group_by `
            -AlignLeft `
                UseBucketKey, VersioningStatus, EnableMfaDelete, HasLifecycleRules, `
                BlockPublicAcls, BlockPublicPolicy, IgnorePublicAcls, RestrictPublicBuckets, HasBucketPolicy `
            -PlainText:$_plain_text `
            -NoRowSeparator:$_no_row_separator
    }
}

function Write-BucketRegion
{
    [OutputType([hashtable], [hashtable])]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory)]
        [Amazon.S3.Model.S3Bucket[]]
        $BucketList
    )

    # Use snake_case.
    $_bucket_list = $BucketList

    # Get bucket locations.
    Write-Message -Progress $script:_cmdlet_name 'Retrieving bucket regions.'
    try {
        foreach ($_bucket in $_bucket_list)
        {
            $_bucket_region = (
                Get-S3BucketLocation -Verbose:$false $_bucket.BucketName | Select-Object -ExpandProperty Value
            )
            $_bucket_region = (
                [string]::IsNullOrEmpty($_bucket_region) ? 'us-east-1' : $_bucket_region
            )
            $_bucket | Add-Member 'BucketRegion' $_bucket_region -Force
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Get-BucketMetric
{
    [OutputType([hashtable], [hashtable])]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory)]
        [Amazon.S3.Model.S3Bucket[]]
        $BucketList
    )

    # Use snake_case.
    $_bucket_list = $BucketList

    # Define lookup hash tables.
    $_bucket_size_lookup = @{}
    $_num_objects_lookup = @{}

    # Get account ID.
    Write-Message -Progress $script:_cmdlet_name 'Retrieving Account ID.'
    $_account_id = Get-STSCallerIdentity -Verbose:$false | Select-Object -ExpandProperty Account

    # Get bucket metrics.
    Write-Message -Progress $script:_cmdlet_name 'Retrieving bucket metrics.'

    # We will collect at least one and at most two data points.
    $_end_utc = (Get-Date).ToUniversalTime()
    $_start_utc = $_end_utc.AddDays(-2).Date

    # We need to retrieve data about our buckets from the region which they reside.
    $_region_list = $_bucket_list | Select-Object -Unique -ExpandProperty BucketRegion

    # To collect available bucket metrics and group them by region.
    $_bucket_size_metric_dict = @{}
    $_num_objects_metric_dict = @{}

    # To construct metric queries and group them by region.
    $_bucket_size_query_dict = @{}
    $_num_objects_query_dict = @{}

    try {
        # Retrieve available metrics.
        foreach ($_region in $_region_list)
        {
            $_bucket_size_metric_dict[$_region] = `
                Get-CWMetricList -Verbose:$false -Namespace 'AWS/S3' -MetricName 'BucketSizeBytes' -Region $_region
            $_num_objects_metric_dict[$_region] = `
                Get-CWMetricList -Verbose:$false -Namespace 'AWS/S3' -MetricName 'NumberOfObjects' -Region $_region
        }

        # Counters for building metric queries.
        $_bucket_size_query_counter = 0
        $_num_objects_query_counter = 0

        # Build queries for bucket size.
        foreach ($_region in $_region_list)
        {
            $_bucket_size_metric_list          = $_bucket_size_metric_dict[$_region]
            $_bucket_size_query_dict[$_region] = foreach ($_metric in $_bucket_size_metric_list)
            {
                $_bucket_size_query_counter++
                [Amazon.CloudWatch.Model.MetricDataQuery]@{
                    AccountId = $_account_id
                    Id = "$($_metric.MetricName.Tolower())_$($_bucket_size_query_counter)"
                    Label = $_metric.Dimensions | Where-Object Name -eq 'BucketName' | Select-Object -Expand Value
                    MetricStat = [Amazon.CloudWatch.Model.MetricStat]@{
                        Period = 86400
                        Stat = 'Average'
                        Metric = [Amazon.CloudWatch.Model.Metric]@{
                            Dimensions = $_metric.Dimensions
                            MetricName = $_metric.MetricName
                            Namespace = $_metric.Namespace
                        }
                    }
                    ReturnData = $true
                }
            }
        }

        # Build queries for num objects
        foreach ($_region in $_region_list)
        {
            $_num_objects_metric_list          = $_num_objects_metric_dict[$_region]
            $_num_objects_query_dict[$_region] = foreach ($_metric in $_num_objects_metric_list)
            {
                $_num_objects_query_counter++
                [Amazon.CloudWatch.Model.MetricDataQuery]@{
                    AccountId = $_account_id
                    Id = "$($_metric.MetricName.ToLower())_$($_num_objects_query_counter)"
                    Label = $_metric.Dimensions | Where-Object Name -eq 'BucketName' | Select-Object -Expand Value
                    MetricStat = [Amazon.CloudWatch.Model.MetricStat]@{
                        Period = 86400
                        Stat = 'Average'
                        Metric = [Amazon.CloudWatch.Model.Metric]@{
                            Dimensions = $_metric.Dimensions
                            MetricName = $_metric.MetricName
                            Namespace = $_metric.Namespace
                        }
                    }
                    ReturnData = true
                }
            }
        }

        # Retrieve datapoints for bucket size.
        $_bucket_size_datapoints = foreach ($_region in $_region_list)
        {
            $_bucket_size_query_list = $_bucket_size_query_dict[$_region]
            Get-CWMetricData -Verbose:$false  `
                -Region $_region `
                -MetricDataQuery $_bucket_size_query_list `
                -StartTime $_start_utc `
                -EndTime $_end_utc `
                -ScanBy TimestampDescending | Select-Object -ExpandProperty MetricDataResults
        }

        # Retrieve datapoints for num objects.
        $_num_objects_datapoints = foreach ($_region in $_region_list)
        {
            $_num_objects_query_list = $_num_objects_query_dict[$_region]
            Get-CWMetricData -Verbose:$false `
                -Region $_region `
                -MetricDataQuery $_num_objects_query_list `
                -StartTime $_start_utc `
                -EndTime $_end_utc `
                -ScanBy TimestampDescending | Select-Object -ExpandProperty MetricDataResults
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Populate bucket size lookup.
    foreach ($_datapoint in $_bucket_size_datapoints)
    {
        if ($_datapoint.Values.Count -gt 0)
        {
            $_bucket_name = $_datapoint.Label
            $_bucket_size = New-ByteInfo $_datapoint.Values[0]
            $_bucket_size_lookup[$_bucket_name] = $_bucket_size
        }
    }

    # Populate num objects lookup.
    foreach ($_datapoint in $_num_objects_datapoints)
    {
        if ($_datapoint.Values.Count -gt 0)
        {
            $_bucket_name = $_datapoint.Label
            $_num_objects = New-NumberInfo $_datapoint.Values[0]
            $_num_objects_lookup[$_bucket_name] = $_num_objects
        }
    }

    # Return metric data.
    return $_bucket_size_lookup, $_num_objects_lookup
}

function Get-BucketVersioning
{
    [OutputType([hashtable], [hashtable])]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory)]
        [Amazon.S3.Model.S3Bucket[]]
        $BucketList
    )

    # Use snake_case.
    $_bucket_list = $BucketList

    # Define lookup hash tables.
    $_versioning_lookup = @{}
    $_has_lifecycle_lookup = @{}

    try {
        Write-Message -Progress $script:_cmdlet_name 'Retrieving bucket versioning configuration.'
        foreach ($_bucket in $_bucket_list)
        {
            $_versioning_lookup[$_bucket.BucketName] = `
                Get-S3BucketVersioning -Verbose:$false -Region $_bucket.BucketRegion $_bucket.BucketName
        }

        Write-Message -Progress $script:_cmdlet_name 'Retrieving bucket lifecycle rules.'
        foreach ($_bucket in $_bucket_list)
        {
            $_has_lifecycle_lookup[$_bucket.BucketName] = (
                Get-S3LifecycleConfiguration -Verbose:$false -Region $_bucket.BucketRegion $_bucket.BucketName |
                Select-Object -ExpandProperty Rules |
                Measure-Object |
                Select-Object -ExpandProperty Count
            ) -gt 0 ?? $false
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Return bucket versioning.
    return $_versioning_lookup, $_has_lifecycle_lookup
}

function Get-BucketEncryption
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory)]
        [Amazon.S3.Model.S3Bucket[]]
        $BucketList
    )

    # Use snake_case.
    $_bucket_list = $BucketList

    # Define lookup hash table.
    $_encryption_lookup = @{}

    Write-Message -Progress $script:_cmdlet_name 'Retrieving bucket encryption settings.'
    try {
        foreach ($_bucket in $_bucket_list)
        {
            $_encryption_lookup[$_bucket.BucketName] = `
                Get-S3BucketEncryption -Verbose:$false -Region $_bucket.BucketRegion $_bucket.BucketName |
                Select-Object -ExpandProperty ServerSideEncryptionRules | Select-Object -First 1
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Return bucket encryption.
    return $_encryption_lookup
}

function Get-BucketPermission
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory)]
        [Amazon.S3.Model.S3Bucket[]]
        $BucketList
    )

    # Use snake_case.
    $_bucket_list = $BucketList

    # Define lookup hash tables.
    $_bpa_lookup               = @{}
    $_has_bucket_policy_lookup = @{}

    # Retrieve BPA.
    Write-Message -Progress $script:_cmdlet_name 'Retrieving bucket block public access settings.'
    try {
        foreach ($_bucket in $_bucket_list)
        {
            $_bpa_lookup[$_bucket.BucketName] = `
                Get-S3PublicAccessBlock -Verbose:$false -Region $_bucket.BucketRegion $_bucket.BucketName
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Retrieve bucket policy - might have to modify code after Get-S3BucketPolicy bug is fixed.
    Write-Message -Progress $script:_cmdlet_name 'Retrieving bucket policies.'
    try {
        foreach ($_bucket in $_bucket_list)
        {
            $_has_bucket_policy_lookup[$_bucket.BucketName] = `
                Get-S3BucketPolicy -Verbose:$false -Region $_bucket.BucketRegion $_bucket.BucketName |
                Test-Json -ErrorAction SilentlyContinue
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Return bucket encryption.
    return $_bpa_lookup, $_has_bucket_policy_lookup
}