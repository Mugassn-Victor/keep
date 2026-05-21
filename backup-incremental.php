<?php
// ==================== 配置区域 ====================
// 数据库配置（如果不需要备份数据库，留空即可）
define('DB_HOST', 'localhost');
define('DB_PORT', 3306);
define('DB_USER', 'root');
define('DB_PASS', 'your_db_password');
define('DB_NAME', 'your_database');
define('DB_CHARSET', 'utf8mb4');
// ==================================================

set_time_limit(0);
ini_set('memory_limit', '256M');

// 自动检测超时时间
$maxExecutionTime = ini_get('max_execution_time');
if ($maxExecutionTime == 0) {
    // 0 表示无限制，不需要分批处理
    define('MAX_EXECUTION_TIME', 0);
    define('USE_INCREMENTAL', false);
} else {
    // 留出 20% 的缓冲时间
    define('MAX_EXECUTION_TIME', max(10, $maxExecutionTime * 0.8));
    define('USE_INCREMENTAL', true);
}

$startTime = microtime(true);

function getDomainName() {
    $domain = $_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? 'localhost';
    $domain = preg_replace('/:\d+$/', '', $domain);
    $domain = preg_replace('/[^a-zA-Z0-9.-]/', '_', $domain);
    return $domain;
}

function isTimeUp($startTime) {
    if (!USE_INCREMENTAL) {
        return false; // 无限制，永不超时
    }
    return (microtime(true) - $startTime) >= MAX_EXECUTION_TIME;
}

$domain = getDomainName();
$zipFileName = $domain . '.zip';
$zipFilePath = __DIR__ . DIRECTORY_SEPARATOR . $zipFileName;
$progressFile = __DIR__ . DIRECTORY_SEPARATOR . '.backup_progress.json';

header('Content-Type: text/plain; charset=utf-8');

// 如果是查询模式，显示环境信息
if (isset($_GET['info'])) {
    $maxExecutionTime = ini_get('max_execution_time');
    $memoryLimit = ini_get('memory_limit');
    echo "PHP max_execution_time: " . ($maxExecutionTime == 0 ? '无限制' : $maxExecutionTime . '秒') . "\n";
    echo "实际使用时间: " . (USE_INCREMENTAL ? MAX_EXECUTION_TIME . '秒' : '无限制') . "\n";
    echo "内存限制: " . $memoryLimit . "\n";
    echo "增量模式: " . (USE_INCREMENTAL ? '是' : '否');
    exit;
}

// 删除操作
if (isset($_GET['d'])) {
    if (file_exists($zipFilePath)) {
        unlink($zipFilePath);
        if (file_exists($progressFile)) unlink($progressFile);
        echo "success";
    } else {
        echo "not found";
    }
    exit;
}

// 压缩操作
$progress = [];
if (file_exists($progressFile)) {
    $progress = json_decode(file_get_contents($progressFile), true);
}

// 初始化进度
if (empty($progress)) {
    $progress = [
        'status' => 'scanning',
        'files' => [],
        'processed' => 0,
        'total' => 0,
        'start_time' => time()
    ];
    
    // 扫描所有文件
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator(__DIR__, RecursiveDirectoryIterator::SKIP_DOTS),
        RecursiveIteratorIterator::SELF_FIRST
    );
    
    foreach ($iterator as $file) {
        if (isTimeUp($startTime)) {
            // 扫描超时，保存进度
            file_put_contents($progressFile, json_encode($progress));
            echo "progress:scanning";
            exit;
        }
        
        $relativePath = str_replace(__DIR__ . DIRECTORY_SEPARATOR, '', $file->getPathname());
        
        // 排除自身和进度文件
        if ($relativePath === basename(__FILE__) || 
            $relativePath === '.backup_progress.json' ||
            $relativePath === $zipFileName) {
            continue;
        }
        
        $progress['files'][] = $relativePath;
    }
    
    $progress['total'] = count($progress['files']);
    $progress['status'] = 'compressing';
    
    // 删除旧的压缩包
    if (file_exists($zipFilePath)) {
        unlink($zipFilePath);
    }
}

// 打开或创建 ZIP
$zip = new ZipArchive();
$mode = file_exists($zipFilePath) ? ZipArchive::CREATE : ZipArchive::CREATE;
if ($zip->open($zipFilePath, $mode) !== TRUE) {
    die('ERROR: 无法创建ZIP文件');
}

// 处理文件直到时间用完
$processed = 0;
$startIndex = $progress['processed'];

for ($i = $startIndex; $i < $progress['total']; $i++) {
    // 检查时间
    if (isTimeUp($startTime)) {
        break;
    }
    
    $relativePath = $progress['files'][$i];
    $fullPath = __DIR__ . DIRECTORY_SEPARATOR . $relativePath;
    
    if (is_dir($fullPath)) {
        $zip->addEmptyDir($relativePath);
    } elseif (is_file($fullPath)) {
        $zip->addFile($fullPath, $relativePath);
    }
    
    $processed++;
    $progress['processed']++;
}

$zip->close();

// 保存进度
file_put_contents($progressFile, json_encode($progress));

// 检查是否完成
if ($progress['processed'] >= $progress['total']) {
    // 压缩完成，删除进度文件
    unlink($progressFile);
    echo "success";
} else {
    // 返回进度百分比和超时信息
    $percent = round(($progress['processed'] / $progress['total']) * 100, 1);
    $timeoutInfo = USE_INCREMENTAL ? MAX_EXECUTION_TIME . 's' : '无限制';
    echo "progress:{$percent}%|timeout:{$timeoutInfo}|files:{$progress['processed']}/{$progress['total']}";
}
