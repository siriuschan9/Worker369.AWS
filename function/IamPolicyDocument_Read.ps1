function Read-IamPolicyDocument
{
    [CmdletBinding()]
    [Alias('iam_policy_doc_read')]
    param (
        [Parameter(ValueFromPipeline, Position = 0)]
        [string]
        $PolicyDocument
    )

    BEGIN
    {
        $_not     = $PSStyle.Formatting.Error
        $_bracket = $PSStyle.Dim
        $_reset   = $PSStyle.Reset
        $_func    = $PSStyle.Formatting.Warning
        $_args    = $PSStyle.Formatting.FeedbackText

        $_open_bracket  = "$($_bracket)($($_reset)"
        $_close_bracket = "$($_bracket))$($_reset)"
    }

    PROCESS
    {
        $_policy_doc = $PolicyDocument
        $_policy_obj = ConvertFrom-Json -Depth 5 $_policy_doc

        $_results = foreach ($_statement in $_policy_obj.Statement)
        {
            $_effect        = $_statement.Effect ?? 'Allow'
            $_condition     = $_statement.Condition

            $_action        = $_statement.Action    | Sort-Object
            $_not_action    = $_statement.NotAction | Sort-Object | Foreach-Object {
                "$($_not)$($_)$($_reset)"
            }

            $_resource      = $_statement.Resource    | Where-Object {$null -ne $_} | Sort-Object
            $_not_resource  = $_statement.NotResource | Where-Object {$null -ne $_} | Sort-Object | ForEach-Object {
                "$($_not)$($_)$($_reset)"
            }

            $_principal            = $_statement.Principal
            $_not_principal        = $_statement.NotPrincipal
            $_not_principal_marker = $_not_principal ? $_not : ''

            $_principal_tranformed = foreach ($_entry in ($_principal ?? $_not_principal))
            {
                if ($_entry.GetType().Name -eq 'PSCustomObject')
                {
                    foreach($_property in $_entry.psobject.Properties)
                    {
                        "$($_not_principal_marker)$($_property.Name):$($_reset)"
                        foreach($_value in $_property.Value)
                        {
                            "  $($_not_principal_marker)- $($_value)$($_reset)"
                        }
                    }
                }
                else
                {
                    "$($_not_principal_marker)$($_entry)$($_reset))"
                }
            }

            $_condition_transformed = foreach ($_entry in $_condition)
            {
                foreach ($_property in $_entry.psobject.Properties)
                {
                    $_this_func = "$($_func)$($_property.Name)$($_reset)"
                    $_this_args = "$($_args)$($_property.Value.psobject.Properties.Name)$($_reset)"

                    "$($_this_func) $($_open_bracket)$($_this_args)$($_close_bracket)"
                }
                foreach ($_value in $_property.Value.psobject.Properties.Value)
                {
                    "  - $($_value)"
                }
            }
            [PSCustomObject]@{
                Effect    = $_effect
                Action    = $_action ?? $_not_action
                Resource  = $_resource ?? $_not_resource
                Principal = $_principal_tranformed
                Condition = $_condition_transformed
            }
        }
        $_results | Format-Column -GroupBy Effect
    }
}