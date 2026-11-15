function ForEach-AwsAccount
{
    [CmdletBinding()]
    [Alias('aws_foreach')]
    param (
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [string[]]
        $ProfileName,

        [Parameter(Position = 1)]
        [scriptblock]
        $Map,

        [switch]
        $AddAwsAccountProperty
    )

    BEGIN
    {
        $_profile_name_list = [System.Collections.Generic.List[string]]::new()
        $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

        if (-not ($_current_profile_account_id = Get-AWSCredential |  Select-Object -ExpandProperty AccountId))  {
            $_matched_credential_list = Get-AWSCredential -ListProfileDetail | ForEach-Object {
                $_profile = Get-AWSCredential $_.ProfileName
                $_profile | Add-Member ProfileName $_.ProfileName
            } | Where-Object AccountId -eq $_current_profile_account_id

            if ($_matched_credential_list.Count -eq 1) {
                $_restore_profile = $_matched_credential_list[0].AccountId
            }
            else {
                Write-Warning 'Current shell credentail will be cleared after running this cmdlet.'
            }
        }
    }

    PROCESS
    {
        $_profile_name_list.AddRange($ProfileName)
    }

    END
    {
        $_map                      = $Map
        $_add_aws_account_property = $AddAwsAccountProperty.IsPresent

        foreach ($_profile_name in $_profile_name_list)
        {
            Write-Message -Progress $_cmdlet_name "Processing Profile `"$($_profile_name)`"."
            Set-AWSCredential $_profile_name
            $_results = & $_map
            if ($_add_aws_account_property){
                $_account_info  = Get-ACCTAccountInformation -Verbose:$false
                $_account_value = "$($_account_info.AccountId) | $($_account_info.AccountName)"
                foreach ($_item in $_results) {
                    $_item | Add-Member 'AwsAccount' $_account_value
                }
            }
            $_results
        }
        $_restore_profile ? (Set-AWSCredential $_restore_profile) : (Clear-AWSCredential)
    }
}