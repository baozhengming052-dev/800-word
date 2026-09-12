@echo off
chcp 65001 >nul
echo ========================================
echo  自动推送到 GitHub
echo ========================================
echo.

cd /d "C:\Users\ASUS\Desktop\花生800词\Words800App"

echo [1/3] 取消之前的合并操作...
git rebase --abort 2>nul

echo [2/3] 准备推送到 GitHub...
echo 注意：这将覆盖 GitHub 上的旧代码
echo.

echo [3/3] 开始推送...
git push -f origin main

if %errorlevel% equ 0 (
    echo.
    echo ========================================
    echo  ✓ 推送成功！
    echo ========================================
    echo.
    echo 下一步：
    echo 1. 访问 https://github.com/baozhengming052-dev/800-word-app
    echo 2. 点击 Actions 标签
    echo 3. 运行 "Build IPA" 工作流
    echo 4. 等待 5-10 分钟后下载 IPA
    echo.
) else (
    echo.
    echo ========================================
    echo  ✗ 推送失败
    echo ========================================
    echo.
    echo 可能的原因：
    echo 1. 网络连接问题
    echo 2. 需要 GitHub 认证
    echo.
    echo 解决方法：
    echo - 使用 GitHub Desktop（推荐）
    echo - 或者手动上传文件到 GitHub 网页
    echo.
)

pause
