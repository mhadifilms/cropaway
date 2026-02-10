// Resolve WPF vs WinForms/System.Drawing type ambiguities.
// UseWindowsForms is enabled in the .csproj for FolderBrowserDialog,
// which pulls in System.Drawing and System.Windows.Forms namespaces
// that conflict with WPF types. These global aliases ensure all files
// default to the WPF types.

global using Point = System.Windows.Point;
global using Size = System.Windows.Size;
global using Rect = System.Windows.Rect;
global using Brush = System.Windows.Media.Brush;
global using Pen = System.Windows.Media.Pen;
global using Rectangle = System.Windows.Shapes.Rectangle;
global using Application = System.Windows.Application;
global using UserControl = System.Windows.Controls.UserControl;
global using MouseEventArgs = System.Windows.Input.MouseEventArgs;
global using KeyEventArgs = System.Windows.Input.KeyEventArgs;
global using DragEventArgs = System.Windows.DragEventArgs;
global using MediaElement = System.Windows.Controls.MediaElement;
global using MediaState = System.Windows.Controls.MediaState;
