using namespace System.Management.Automation

function Write-MfaProfile
{
    <#
    .SYNOPSIS
    This cmdlet requests temporary credentials from AWS STS service and
    saves it to the shared credential store (i.e. ~/aws/credentials).

    .DESCRIPTION
    This cmdlet reads a source profile from the credential stores (e.g. ~/.aws/credentials),
    plus a MFA token code from user input.
    It thens request a temporary credential from AWS STS service using the source profile and the token code.
    The temporary credential is written to the shared credential store as a new profile named <source profile>_mfa.
    If the MFA profile is already present, it will be overwritten.

    .PARAMETER SourceProfile
    The name of the profile from the credential store (i.e. ~/.aws/credentials) to extract the source credentials.

    .PARAMETER TokenCode
    The six-digits token code from the MFA device.

    .PARAMETER SerialNumber
    The serial number of the MFA device, e.g. arn:aws:iam::123456789012:mfa/user.
    If this is not specified, the cmdlet attempts to retrieve it from the shell variable $AWS_MFA,
    which is expected to be a hashtable of profile name -> MFA serial number.
    If this retrieval does not succeed, the cmdlet attempts to read MFA devices from the AWS IAM service.
    If there are multiple MFA devices, the cmdlet terminates with an error.
    If there is only one MFA device, the cmdlet will use this MFA to request for the temporary credential.

    .PARAMETER DurationInSeconds
    The duration in seconds before the session token expires. Default is set to 86400 (24 hours).

    .PARAMETER DoNotSetAsDefaultCredential
    When set, this cmdlet will NOT load the written MFA profile as the default credentials.
    By default, the cmdlet will load the written MFA profile as the default credentials - $StoredAWSCredentials.

    .EXAMPLE
    Write-MFAProfile my_profile 123456

    This cmdlet reads a source profile named "my_profile" from the available credential stores.
    It then requests for a temporary credential from STS using the source profile credential and the token code,
    and saves that temporaray credential to a separate profile named "my_profile_mfa".
    #>
    [Alias("mfa")]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [String]
        $SourceProfile,

        [Parameter(Mandatory, Position = 1)]
        [ValidatePattern('\d{6}')]
        [String]
        $TokenCode,

        [Parameter()]
        [String]
        $SerialNumber,

        [Parameter()]
        [ValidateRange(900, 129600)] # 15 min to 36 hours
        [Int32]
        $DurationInSeconds = 86400,  # Default 24 hours

        [Parameter()]
        [SwitchParameter]
        $DoNotSetAsDefaultCredential
    )

    # For easy pickup.
    $_cmdlet_name = $MyInvocation.MyCommand.Name

    # Use snake_case.
    $_profile_name     = $SourceProfile
    $_token_code       = $TokenCode
    $_serial_number    = $SerialNumber
    $_duration         = $DurationInSeconds
    $_mfa_profile_name = "$($_profile_name)_mfa"
    $_set_default_cred = -not $DoNotSetAsDefaultCredential.IsPresent

    # Check if profile exists.
    if(-not (Get-AWSCredential $_profile_name))
    {
        $_error_record = New-ErrorRecord `
            -ErrorMessage 'Profile not found in credential stores.' `
            -ErrorId 'ProfileNotFound' `
            -ErrorCategory ObjectNotFound

        $PSCmdlet.ThrowTerminatingError($_error_record)
    }

    # Check if AWS CLI is installed.
    if(-not (Get-Command aws -ErrorAction SilentlyContinue))
    {
        $_error_record = New-ErrorRecord `
            -ErrorMessage 'AWS CLI is not installed. Please install it to proceed.' `
            -ErrorId 'AwsCliNotInstalled' `
            -ErrorCategory ObjectNotFound

        $PSCmdlet.ThrowTerminatingError($_error_record)
    }

    try{
        # 1. Get MFA device info.
        Write-Message -Progress $_cmdlet_name -Message 'Processing MFA device info.'

        if(-not $_serial_number)
        {
            # Try to pick up MFA serial number from shell variable.
            if($AWS_MFA -and $AWS_MFA.ContainsKey($_profile_name))
            {
                $_serial_number = $AWS_MFA[$_profile_name]
            }
            else
            {
                # Get all MFA devices.
                $_serial_number_list = @(
                    Get-IAMVirtualMFADevice -Verbose:$false -ProfileName $_profile_name |
                    Where-Object SerialNumber -match 'arn:aws:iam::\d{12}:mfa\/.*' |
                    Select-Object -ExpandProperty SerialNumber
                )

                # Terminate function if there is no MFA device set up.
                if($_serial_number_list.Length -eq 0)
                {
                    $_error_record = New-ErrorRecord `
                        -ErrorMessage 'No MFA device found. Please set up one MFA device first.' `
                        -ErrorId 'MfaDeviceNotFound' `
                        -ErrorCategory ResourceUnavailable

                    $PSCmdlet.ThrowTerminatingError($_error_record)
                }

                # Terminate function if there are multiple MFA devices set up. We do not know which one to use.
                if($_serial_number_list.Length -gt 1)
                {
                    $_error_record = New-ErrorRecord `
                        -ErrorMessage 'Multiple MFA devices found. Use -SerialNumber parameter to identify the MFA.' `
                        -ErrorId 'MultipleMfaDevices' `
                        -ErrorCategory NotSpecified

                    $PSCmdlet.ThrowTerminatingError($_error_record)
                }

                # There is only one MFA device. So, let's use this serial number.
                $_serial_number = $_serial_number_list[0]
            }
        }

        # 2. Get temp credential.
        Write-Message -Progress $_cmdlet_name 'Requesting for temporary credentials.'
        $_get_token_params = @{
            ProfileName       = $_profile_name
            SerialNumber      = $_serial_number
            TokenCode         = $_token_code
            DurationInSeconds = $_duration
            Verbose           = $false
        }
        $_temp_cred = Get-STSSessionToken @_get_token_params

        # 3. Write MFA profile to credential file.
        Write-Message -Progress $_cmdlet_name 'Writing MFA profile.'
        aws configure set aws_access_key_id     $($_temp_cred.AccessKeyId)     --profile $_mfa_profile_name
        aws configure set aws_secret_access_key $($_temp_cred.SecretAccessKey) --profile $_mfa_profile_name
        aws configure set aws_session_token     $($_temp_cred.SessionToken)    --profile $_mfa_profile_name

        if($_profile_region = Invoke-Command {aws configure get region --profile $_profile_name})
        {
            aws configure set region $_profile_region --profile $_mfa_profile_name
        }

        if($_profile_output = Invoke-Command {aws configure get output --profile $_profile_name})
        {
            aws configure set output $_profile_output --profile $_mfa_profile_name
        }

        Write-Message -Output "MFA profile '$_mfa_profile_name' written successfully."

        # 4. Load credential from MFA profile to $StoredAWSCredentials.
        if($_set_default_cred)
        {
            Set-AWSCredential $_mfa_profile_name -Scope Global -Verbose:$false
            Write-Message -Output "MFA profile '$_mfa_profile_name' loaded as default credential."
        }
    }
    catch{
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }
}