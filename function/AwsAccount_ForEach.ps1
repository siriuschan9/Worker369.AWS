function ForEach-AwsAccount
{
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [string[]]
        $ProfileName,

        [Parameter(Position = 1)]
        [scriptblock]
        $Map
    )

    BEGIN
    {
        $_profile_name_list = [System.Collections.Generic.List[string]]::new()
    }

    PROCESS
    {
        $_profile_name_list.AddRange($ProfileName)
    }

    END
    {
        $_map = $Map

        foreach ($_profile_name in $_profile_name_list)
        {
            Set-AWSCredential $_profile_name
            & $_map
        }
    }
}