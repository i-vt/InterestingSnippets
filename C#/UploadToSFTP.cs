using Renci.SshNet; // SSH.NET namespace

public static void UploadFileToSftp(string strHost, int intPort, string strUsername, string strPassword, string strLocalFilePath, string strRemoteDirectory)
{
    // Setup Credentials and Server Information
    ConnectionInfo ConnNfo = new ConnectionInfo(strHost, intPort, strUsername,
        new AuthenticationMethod[]
        {
            // Password based Authentication
            new PasswordAuthenticationMethod(strUsername,strPassword),
        }
    );

    // Execute a (S)FTP command
    using (var sftp = new SftpClient(ConnNfo))
    {
        sftp.Connect(); // Connect to the server

        // If the directory doesn't exist, create it
        if (!sftp.Exists(strRemoteDirectory))
        {
            sftp.CreateDirectory(strRemoteDirectory);
        }

        // Upload the file
        using (var fileStream = new FileStream(strLocalFilePath, FileMode.Open))
        {
            sftp.UploadFile(fileStream, Path.Combine(strRemoteDirectory, Path.GetFileName(strLocalFilePath)));
        }

        sftp.Disconnect(); // Disconnect from the server
    }
}
