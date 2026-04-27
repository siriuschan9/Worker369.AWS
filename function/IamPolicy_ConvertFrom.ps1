function Convert-IamPolicy
{
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [string]
        $PolicyDocument
    )

    PROCESS
    {
        $_policy_doc = $PolicyDocument
        $_policy_obj = ConvertFrom-Json -Depth 5 $_policy_doc

        $_results = foreach ($_statement in $_policy_obj.Statement)
        {
            $_effect    = $_statement.Effect ?? 'Allow'
            $_action    = $_statement.Action | Sort-Object | ForEach-Object { "- $($_)"}
            $_resource  = $_statement.Resource | Where-Object {$null -ne $_} | Sort-Object | ForEach-Object { "- $($_)"}
            $_principal = $_statement.Principal
            $_condition = $_statement.Condition

            $_principal_tranformed = foreach ($_entry in $_principal)
            {
                if ($_entry.GetType().Name -eq 'PSCustomObject')
                {
                    foreach($_property in $_entry.psobject.Properties)
                    {
                        "- $($_property.Name):"
                        foreach($_value in $_property.Value)
                        {
                            "  - $($_value)"
                        }
                    }
                }
                else
                {
                    "- $($_entry)"
                }
            }

            $_condition_transformed = foreach ($_entry in $_condition)
            {
                foreach ($_property in $_entry.psobject.Properties)
                {
                    "- $($_property.Name)($($_property.Value.psobject.Properties.Name)"
                }
                foreach ($_value in $_property.Value.psobject.Properties.Value)
                {
                    "  - $($_value)"
                }
            }
            [PSCustomObject]@{
                Effect    = $_effect
                Action    = $_action
                Resource  = $_resource
                Principal = $_principal_tranformed
                Condition = $_condition_transformed
            }
        }
        $_results | Format-Column -GroupBy Effect
    }
}

<#
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "TlsRequestsOnly",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::369-s3-z-work-all-accrvw-051826723662-01/*",
                "arn:aws:s3:::369-s3-z-work-all-accrvw-051826723662-01"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::051826723662:role/DefaultEC2InstanceRole"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::369-s3-z-work-all-accrvw-051826723662-01/*"
        }
    ]
}
#>