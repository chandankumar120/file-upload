<?php
session_start(); // Start session to store messages

// Error reporting (remove in production)
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Define upload directory
$upload_dir = 'uploaded_data/';

// Create upload directory if it doesn't exist
if (!file_exists($upload_dir)) {
    mkdir($upload_dir, 0777, true);
}

// File upload handler
if(isset($_FILES['fileToUpload'])) {
    // Sanitize filename
    $filename = preg_replace("/[^a-zA-Z0-9.]/", "", basename($_FILES['fileToUpload']['name']));
    
    // Generate unique filename to prevent overwriting
    $unique_filename = uniqid() . '_' . $filename;
    $target_file = $upload_dir . $unique_filename;

    // File size limit (1GB)
    $max_file_size = 1024 * 1024 * 1024;
    
    // All file types are now allowed
    $file_extension = strtolower(pathinfo($filename, PATHINFO_EXTENSION));

    // Validation checks
    if ($_FILES['fileToUpload']['size'] > $max_file_size) {
        $_SESSION['upload_message'] = "Sorry, your file is too large. Maximum file size is 1GB.";
        $_SESSION['upload_status'] = 'danger';
    } else {
        // Try to upload file
        if (move_uploaded_file($_FILES['fileToUpload']['tmp_name'], $target_file)) {
            $_SESSION['upload_message'] = "The file ". htmlspecialchars($filename). " has been uploaded successfully.";
            $_SESSION['upload_status'] = 'success';
        } else {
            $_SESSION['upload_message'] = "Sorry, there was an error uploading your file.";
            $_SESSION['upload_status'] = 'danger';
        }
    }

    // Redirect to prevent form resubmission
    header('Location: ' . $_SERVER['PHP_SELF']);
    exit;
}

// File download handler
if(isset($_GET['download'])) {
    $filename = $_GET['download'];
    $filepath = $upload_dir . $filename;

    // Check if file exists
    if (file_exists($filepath)) {
        // Get original filename (remove unique prefix)
        $original_filename = preg_replace('/^[^_]*_/', '', $filename);

        // Force download
        header('Content-Description: File Transfer');
        header('Content-Type: application/octet-stream');
        header('Content-Disposition: attachment; filename="' . $original_filename . '"');
        header('Expires: 0');
        header('Cache-Control: must-revalidate');
        header('Pragma: public');
        header('Content-Length: ' . filesize($filepath));
        readfile($filepath);
        exit;
    } else {
        echo "File not found.";
        exit;
    }
}

// File delete handler
if(isset($_GET['delete'])) {
    $filename = $_GET['delete'];
    $filepath = $upload_dir . $filename;

    // Check if file exists
    if (file_exists($filepath)) {
        if (unlink($filepath)) {
            $_SESSION['upload_message'] = "File deleted successfully.";
            $_SESSION['upload_status'] = 'success';
        } else {
            $_SESSION['upload_message'] = "Error deleting file.";
            $_SESSION['upload_status'] = 'danger';
        }
    }

    // Redirect to prevent reloading delete action
    header('Location: ' . $_SERVER['PHP_SELF']);
    exit;
}

// Function to list uploaded files with additional info
function listUploadedFiles($upload_dir) {
    $files = array_diff(scandir($upload_dir), array('..', '.'));
    $file_details = [];
    
    foreach ($files as $file) {
        $filepath = $upload_dir . $file;
        $original_filename = preg_replace('/^[^_]*_/', '', $file);
        $file_details[] = [
            'unique_name' => $file,
            'original_name' => $original_filename,
            'size' => round(filesize($filepath) / 1024, 2),
            'type' => strtoupper(pathinfo($original_filename, PATHINFO_EXTENSION))
        ];
    }
    
    return $file_details;
}

// Retrieve and clear flash messages
$upload_message = isset($_SESSION['upload_message']) ? $_SESSION['upload_message'] : '';
$upload_status = isset($_SESSION['upload_status']) ? $_SESSION['upload_status'] : '';
unset($_SESSION['upload_message'], $_SESSION['upload_status']);
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>File Upload System</title>
    <!-- Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <!-- Bootstrap Icons -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css" rel="stylesheet">
    <style>
        body {
            background-color: #f4f6f9;
        }
        .upload-container {
            max-width: 700px;
            margin: 50px auto;
            background-color: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .file-list {
            max-height: 300px;
            overflow-y: auto;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="upload-container">
            <h2 class="text-center mb-4">📁 File Upload System</h2>
            
            <?php if ($upload_message): ?>
                <div class="alert alert-<?php echo $upload_status; ?> alert-dismissible fade show" role="alert">
                    <?php echo $upload_message; ?>
                    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
                </div>
            <?php endif; ?>

            <form action="" method="post" enctype="multipart/form-data">
                <div class="mb-3">
                    <label for="fileToUpload" class="form-label">Select File to Upload</label>
                    <input 
                        class="form-control" 
                        type="file" 
                        name="fileToUpload" 
                        id="fileToUpload" 
                        required
                    >
                    <small class="text-muted">Max file size: 1GB. All file types are allowed.</small>
                </div>
                <div class="d-grid">
                    <button type="submit" class="btn btn-primary">
                        <i class="bi bi-cloud-upload"></i> Upload File
                    </button>
                </div>
            </form>

            <hr>

            <h3 class="mt-4">📋 Uploaded Files</h3>
            <div class="file-list">
                <?php 
                $uploaded_files = listUploadedFiles($upload_dir);
                if (count($uploaded_files) > 0): 
                ?>
                    <table class="table table-striped">
                        <thead>
                            <tr>
                                <th>Filename</th>
                                <th>Type</th>
                                <th>Size (KB)</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                        <?php foreach($uploaded_files as $file): ?>
                            <tr>
                                <td><?php echo htmlspecialchars($file['original_name']); ?></td>
                                <td><?php echo htmlspecialchars($file['type']); ?></td>
                                <td><?php echo $file['size']; ?></td>
                                <td>
                                    <div class="btn-group" role="group">
                                        <a href="?download=<?php echo urlencode($file['unique_name']); ?>" 
                                           class="btn btn-sm btn-outline-primary" 
                                           title="Download">
                                            <i class="bi bi-download"></i>
                                        </a>
                                        <a href="?delete=<?php echo urlencode($file['unique_name']); ?>" 
                                           class="btn btn-sm btn-outline-danger" 
                                           title="Delete"
                                           onclick="return confirm('Are you sure you want to delete this file?');">
                                            <i class="bi bi-trash"></i>
                                        </a>
                                    </div>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                        </tbody>
                    </table>
                <?php else: ?>
                    <p class="text-muted text-center">No files uploaded yet.</p>
                <?php endif; ?>
            </div>
        </div>
    </div>

    <!-- Bootstrap JS and dependencies -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>