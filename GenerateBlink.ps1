blink src\shared\Shatterbox\Shatterbox

$insertAtLine = 6

$files = "src\shared\Shatterbox\core\Blink\Client.luau", "src\shared\Shatterbox\core\Blink\Server.luau"

$lints = "--#selene: allow(unused_variable)", "--#selene: allow(parenthese_conditions)", "--#selene: allow(multiple_statements)"

$newLines = @()
$newLines2 = @()

foreach ($filePath in $files) {
    $lines = Get-Content $filePath
    $newLines = @()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq ($insertAtLine - 1)) {
            foreach ($lint in $lints) {
                $newLines += $lint
            }
        }
        $newLines += $lines[$i]
    }

    $newLines | Set-Content $filePath
}