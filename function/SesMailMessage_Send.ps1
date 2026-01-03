function Send-SesMailMessage
{
    [CmdletBinding()]
    [Alias('ses_send')]
    param (
        [Parameter(Mandatory)]
        [string]
        $From,

        [string[]]
        $To = @(),

        [string[]]
        $Cc = @(),

        [string[]]
        $Bcc = @(),

        [string]
        $Subject = [string]::Empty,

        [string]
        $Text = [string]::Empty,

        [string]
        $Html = [string]::Empty,

        [string[]]
        $Attachment = @()
    )

    # Use snake_case.
    $_from       = $From
    $_to         = $To
    $_cc         = $Cc
    $_bcc        = $Bcc
    $_subject    = $Subject
    $_text       = $Text
    $_html       = $Html
    $_attachment = $Attachment

    # Validate that we have at least one recipient.
    if ($_to.Length -eq 0 -and $_cc.Length -eq 0 -and $_bcc.Length -eq 0)
    {
        $_error_record = New-ErrorRecord `
            -ErrorMessage 'Please specify at least one recipient.' `
            -ErrorId 'OnRecipientSpecified' `
            -ErrorCategory NotSpecified

        $PSCmdlet.ThrowTerminatingError($_error_record)
    }

    # Generate a random ID for our mime boundary.
    $_boundary = (New-Guid | Select-Object -ExpandProperty Guid) -replace '-'

    # Append message header.
    $_raw = [System.Text.StringBuilder]::new()
    $_raw.AppendLine("From: $($_from)") | Out-Null
    if ($_to.Length -gt 0) {
        $_raw.AppendLine("To: $($_to -join ',')") | Out-Null
    }
    if ($_cc.Length -gt 0) {
        $_raw.AppendLine("Cc: $($_cc -join ',')") | Out-Null
    }
    if ($_bcc.Length -gt 0) {
        $_raw.AppendLine("Bcc: $($_bcc -join ',')") | Out-Null
    }
    $_raw.AppendLine("Subject: $($_subject)") | Out-Null
    $_raw.AppendLine("Content-Type: multipart/mixed; boundary=`"$($_boundary)`"") | Out-Null
    $_raw.AppendLine() | Out-Null

    # Append text.
    $_raw.AppendLine("--sub_$($_boundary)") | Out-Null
    $_raw.AppendLine("Content-Type: text/plain; charset=UTF-8") | Out-Null
    $_raw.AppendLine("Content-Transfer-Encoding: quoted-printable") | Out-Null
    $_raw.AppendLine() | Out-Null
    $_raw.AppendLine($_text) | Out-Null
    $_raw.AppendLine() | Out-Null

    # Append html.
    $_raw.AppendLine("--sub_$($_boundary)") | Out-Null
    $_raw.AppendLine("Content-Type: text/html; charset=UTF-8") | Out-Null
    $_raw.AppendLine("Content-Transfer-Encoding: quoted-printable") | Out-Null
    $_raw.AppendLine() | Out-Null
    $_raw.AppendLine($_html) | Out-Null
    $_raw.AppendLine() | Out-Null

    # Close sub boundary.
    $_raw.AppendLine("--sub_$($_boundary)--") | Out-Null
    $_raw.AppendLine() | Out-Null

    # Append attachments.
    foreach ($_att in $_attachment)
    {
        try{
            $_file = Get-Item $_att

            # Load file content into byte array.
            $_bytes = [System.IO.File]::ReadAllBytes($_file.FullName)

            # Convert the byte array to base64 string.
            $_base64 = [Convert]::ToBase64String($_bytes, [System.Base64FormattingOptions]::InsertLineBreaks)

            # Save a reference to the filename.
            $_filename = $_file.FullName | Split-Path -Leaf
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Re-throw caught error.
            $PSCmdlet.ThrowTerminatingError($_)
        }

        $_raw.AppendLine("--$($_boundary)") | Out-Null
        $_raw.AppendLine("Content-Type: application/octet-stream; filename=`"$($_filename)`"") | Out-Null
        $_raw.AppendLine("Content-Description: $($_filename)") | Out-Null
        $_raw.AppendLine("Content-Disposition: attachment; filename=`"$($_filename)`"") | Out-Null
        $_raw.AppendLine("Content-Transfer-Encoding: base64") | Out-Null
        $_raw.AppendLine() | Out-Null
        $_raw.AppendLine($_base64) | Out-Null
        $_raw.AppendLine() | Out-Null
    }

    # Close boundary.
    $_raw.AppendLine("--$($_boundary)--") | Out-Null

    try{
        # Convert UTF string to bytes.
        $_raw_bytes = [System.Text.Encoding]::UTF8.GetBytes($_raw.ToString())

        # Send out the email.
        Send-SES2Email -Raw_Data $_raw_bytes
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }
}