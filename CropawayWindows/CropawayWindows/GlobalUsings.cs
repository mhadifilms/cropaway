// Global using directives for the Cropaway Windows project.
// UseWindowsForms is in the .csproj for FolderBrowserDialog access,
// but its implicit usings (System.Drawing, System.Windows.Forms)
// are removed via <Using Remove="..."/> to prevent WPF conflicts.
// Files that need System.Drawing import it explicitly (CropMaskRenderer).

// Ensure System.IO is always available (implicit usings may not cover it
// in all build environments)
global using System.IO;
