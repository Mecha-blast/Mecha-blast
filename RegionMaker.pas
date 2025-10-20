unit RegionMaker;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  ExtCtrls, StdCtrls, ClipBrd, ComCtrls, ShellAPI, ToolWin, INIFiles;

type
  TForm1 = class(TForm)
    OpenDialog1: TOpenDialog;
    SaveDialog1: TSaveDialog;
    Memo1: TRichEdit;
    Enabled: TImageList;
    Disabled: TImageList;
    ToolBar1: TToolBar;
    OpenButton: TToolButton;
    PasteButton: TToolButton;
    ComboBox1: TComboBox;
    ToolButton3: TToolButton;
    ToolButton4: TToolButton;
    GoButton: TToolButton;
    ToolButton6: TToolButton;
    SaveButton: TToolButton;
    CopyButton: TToolButton;
    ToolButton9: TToolButton;
    TestButton: TToolButton;
    ToolButton11: TToolButton;
    AboutButton: TToolButton;
    Panel1: TPanel;
    Bevel2: TBevel;
    Shape1: TShape;
    Label1: TLabel;
    ToolButton13: TToolButton;
    Panel2: TPanel;
    Image1: TImage;
    Image2: TImage;
    Bevel3: TBevel;
    Bevel1: TBevel;
    procedure Image1MouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure OpenDialog1SelectionChange(Sender: TObject);
    procedure OpenButtonClick(Sender: TObject);
    procedure PasteButtonClick(Sender: TObject);
    procedure GoButtonClick(Sender: TObject);
    procedure SaveButtonClick(Sender: TObject);
    procedure CopyButtonClick(Sender: TObject);
    procedure TestButtonClick(Sender: TObject);
    procedure AboutButtonClick(Sender: TObject);
  private
    { Private declarations }
    procedure WMDROPFILES(var Message:TWMDROPFILES); message WM_DROPFILES;
    procedure WMGETMINMAXINFO(var mmInfo:TWMGETMINMAXINFO); message wm_GetMinMaxInfo;
    // These two procedures handle two Windows messages, which allow me to
    // have files dropped on my form, and allow me to specify the minimum and
    // maximum sizes of my form.
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.DFM}

const
  WindowTitle='Winamp region.txt generator';
  // I declare this as a constant to avoid having to type it every time I
  // change the titlebar text

var
  MyRgn:HRgn;
  // A global variable which is the handle of the region data I'm building.
  // It's global so I can modify it in one procedure and use it in another.

// This procedure updates the mask bitmap
procedure UpdateMask;
begin
  Form1.Image2.Picture.Bitmap.Assign(Form1.Image1.Picture.Bitmap); // Copy image bitmap over
  Form1.Image2.Picture.Bitmap.mask(Form1.Shape1.Brush.Color);      // Mask transparent colour - makes image 1bit
  Form1.Image2.Picture.Bitmap.PixelFormat:=pf24bit;                // Increase colour depth so I can draw red on it - it doesn't work properly if it's less than 24bit, though.
  if Form1.TestButton.Down then begin // remove region if applied
    Form1.TestButton.Down:=false;
    Form1.TestButton.Click;
  end;
end;

// Show warning message if bitmap is non-standard size
procedure CheckSize;
begin
  if (Form1.Image2.Picture.Bitmap.Width<>275)
  or ((Form1.Image2.Picture.Bitmap.Height<>116) and (Form1.Image2.Picture.Bitmap.Height<>14))
  then Application.Messagebox(
    'This image is not a standard Winamp size!'+#13+
    'Normal windows should be 275x116 and windowshaded windows should be 275x14.'
    ,'Warning!',MB_OK+MB_ICONINFORMATION);
  // Also enable some stuff here
  Form1.Combobox1.Enabled:=True;
  Form1.GoButton.Enabled:=True;
//  Form1.ComboBox1.SetFocus;
// This fails when loading from the conmmandline because the combobox isn't there yet
end;

// This function finds the biggest rect with x,y at the top-left which contains
// no white pixels. It's not the fastest method in the world, mainly because
// Pixels[] is slow - ScanLine[] would be faster, but would not allow
// multi-line rects.
function GetRectFrom(const x,y:integer;const bmp:TBitmap):TRect;
var
  w,h:integer;
  i:integer;
  WhiteFoundR,WhiteFoundB:boolean;
begin
  h:=0; w:=0;

  repeat
    WhiteFoundR:=x+w+1=bmp.Width; // Don't bother trying to increase width if we're at the edge already
    if not WhiteFoundR then // if we haven't found the maximum width yet then check column of pixels to the right
      for i:=0 to h do WhiteFoundR:=WhiteFoundR or (bmp.canvas.pixels[x+w+1,y+i]=clWhite);
    if not WhiteFoundR then Inc(w); // if it contains no white then increase width of rect

    // Repeat for downward direction
    WhiteFoundB:=y+h+1=bmp.height;
    if not WhiteFoundB then
      for i:=0 to w do WhiteFoundB:=WhiteFoundB or (bmp.canvas.pixels[x+i,y+h+1]=clWhite);
    if not WhiteFoundB then Inc(h);
  until WhiteFoundB and WhiteFoundR;

  // Put resulting data into a Rect structure
  Result.Left:=x;
  Result.Top:=y;
  Result.Right:=x+w+1;
  Result.Bottom:=y+h+1;

  // Draw this new rect on the mask bitmap, to indicate that those pixels are
  // already included in data; colour them red so they're not black (= pixels
  // not in region data yet) or white (= pixels that shouldn't be in region
  // data)
  with bmp.canvas do begin
    Brush.Color:=clRed;
    fillrect(result);
  end;
end;


procedure TForm1.GoButtonClick(Sender: TObject);
var
  x,y,counter:integer;
  MyRect:TRect;
  PointList,NumPoints:string;
  NotFirst:boolean;
  temprgn:hrgn;
begin
  NotFirst:=False; // I need to know if I'm adding the first rect to the region - see later in this procedure
  UpdateMask; // Initialises mask - in case we've already changed some of it to red, and are re-processing
  NumPoints:='NumPoints='; // Initialise strings
  PointList:='PointList=';
  counter:=0; // Counts number of rects for titlebar info

  // Disable buttons you shouldn't click on when it's working
  OpenButton.Enabled:=False;
  PasteButton.Enabled:=False;
  GoButton.Enabled:=False;
  SaveButton.Enabled:=False;
  CopyButton.Enabled:=False;
  TestButton.Enabled:=False;

  // Set form caption
  Form1.Caption:='Working - '+WindowTitle;
  Application.Title:=Form1.Caption; // Makes taskbar caption match window caption

  for y:=0 to image2.picture.bitmap.height-1 do for x:=0 to image2.picture.bitmap.width-1 do begin // Iterate over entire image
    if image2.picture.bitmap.canvas.pixels[x,y]=clBlack then begin // If pixel is black then do stuff
      Inc(Counter); // Add one to number of rects
      MyRect:=GetRectFrom(x,y,image2.picture.bitmap); // Get rect starting from this pixel
      PointList:=PointList+ // Add rect to PointList string
        IntToStr(MyRect.Left)+','+IntToStr(MyRect.Top)+' '+
        IntToStr(MyRect.Right)+','+IntToStr(MyRect.Top)+' '+
        IntToStr(MyRect.Right)+','+IntToStr(MyRect.Bottom)+' '+
        IntToStr(MyRect.Left)+','+IntToStr(MyRect.Bottom)+' ';
      NumPoints:=NumPoints+'4,'; // And add a bit to the NumPoints to make it work

      // Add it to my region
      if NotFirst then begin // If it's not the first then add to existing region
        temprgn:=CreateRectRgnIndirect(MyRect);
        CombineRgn(MyRgn,MyRgn,temprgn,rgn_or);
        DeleteObject(temprgn);
      end else begin // If it's the first then create the region from it
        MyRgn:=CreateRectRgnIndirect(MyRect);
        NotFirst:=True;
      end;
      Application.ProcessMessages; // Allow the form to update (and show my red pixels appearing)
    end;
  end;

  // Trim trailing comma and space... not really needed but it looks neater
  NumPoints:=copy(NumPoints,1,length(NumPoints)-1);
  PointList:=copy(PointList,1,length(PointList)-1);

  with Memo1.Lines do begin
    Clear; // Delete what's already there (if anything)
    case ComboBox1.ItemIndex of // Add section header
      0: Add('[Normal]');
      1: Add('[Equalizer]');
      2: Add('[WindowShade]');
      3: Add('[EqualizerWS]');
    end;

    // Add my advertisement :o)
    Add('; This region info generated by '+WindowTitle+' which is made by Maxim.');
    Add('; http://winamp.mwos.cjb.net');
    Add('; Note to skin authors: You can remove these comments so long as you leave one copy of the two lines above.');
    // And finally add the data...
    Add(NumPoints);
    Add(PointList);
  end;

  // Move cursor to start of text
  Memo1.SelStart:=0;
  Memo1.SelLength:=0;

  // Put data stats in titlebar
  Form1.Caption:=IntToStr(Counter)+' subregions totalling '+IntToStr(Length(Memo1.Text))+' bytes ('+FloatToStrF(Length(Memo1.Text)/1024,ffFixed,5,2)+'KB) - '+WindowTitle;
  Application.Title:=Form1.Caption;

  // Re-enable buttons I disabled earlier
  OpenButton.Enabled:=True;
  PasteButton.Enabled:=True;
  GoButton.Enabled:=True;
  SaveButton.Enabled:=True;
  CopyButton.Enabled:=True;
  TestButton.Enabled:=True;
end;

procedure TForm1.Image1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  // Select transparent colour when mouse clicked on it, if a bitmap is loaded
  // and it's not processing it already
  if (not Image1.Picture.Bitmap.Empty) and (GoButton.Enabled) then begin
    Shape1.Brush.Color:=Image1.Picture.Bitmap.Canvas.Pixels[x,y];
    UpdateMask;
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  ComboBox1.ItemIndex:=0; // So something apears in the combobox

  Form1.Caption:=WindowTitle; // Set caption
  Application.Title:=Form1.Caption;

  // Load from commandline if necessary
  if (paramcount=1)
  and FileExists(paramstr(1))
  and (lowercase(ExtractFileExt(paramstr(1)))='.bmp')
  then begin
    Image1.Picture.Bitmap.LoadFromFile(paramstr(1));
    SaveDialog1.InitialDir:=ExtractFilePath(paramstr(1));
    UpdateMask;
    CheckSize;
  end;

  DragAcceptFiles(Form1.Handle,True); // allow dropping of files

  Application.HintHidePause:=10000; // 10s hint display

  with TIniFile.Create(extractfilepath(paramstr(0))+'Settings.ini') do begin
    Form1.Left:=ReadInteger('Settings','Left',100);
    Form1.Top:=ReadInteger('Settings','Top',100);
    Form1.Width:=ReadInteger('Settings','Width',570);
    Form1.Height:=ReadInteger('Settings','Height',300);
    Free;
  end;

end;

// Handle dropped files
procedure TForm1.WMDROPFILES(var Message: TWMDROPFILES);
var
  MyPChar:array[0..8191] of char;
  MyString:string;
begin
  DragQueryFile(Message.drop,0,MyPChar,8191); // query the first file (ignore any more)
  dragfinish(message.drop);

  MyString:=StrPas(MyPChar);

  // if it's suitable then load it
  if (FileExists(MyString))
  and (ExtractFileExt(MyString)='.bmp')
  then begin
    Image1.Picture.Bitmap.LoadFromFile(MyString);
    SaveDialog1.InitialDir:=ExtractFilePath(MyString);
    UpdateMask;
    CheckSize;
  end;
end;

// Make the memeo fill the space when for resizes
procedure TForm1.FormResize(Sender: TObject);
begin
  Memo1.SetBounds(Memo1.Left,memo1.Top,Form1.ClientWidth-4,Form1.ClientHeight-150);
end;

// Set minimum form size
procedure TForm1.WMGETMINMAXINFO(var mmInfo:TWMGETMINMAXINFO);
begin
  with mmInfo.minmaxinfo^ do begin
    ptMinTrackSize.x:=558+2*GetSystemMetrics(SM_CXFRAME);
    ptMinTrackSize.y:=180+2*GetSystemMetrics(SM_CYFRAME)+GetSystemMetrics(SM_CYCAPTION);
  end;
end;

// I must release my resources when I exit :o)
procedure TForm1.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  DeleteObject(MyRgn);
  if IsZoomed(Form1.Handle) then ShowWindow(Form1.Handle,sw_restore);
  with TIniFile.Create(extractfilepath(paramstr(0))+'Settings.ini') do begin
    WriteInteger('Settings','Left',Form1.Left);
    WriteInteger('Settings','Top',Form1.Top);
    WriteInteger('Settings','Width',Form1.Width);
    WriteInteger('Settings','Height',Form1.Height);
    Free;
  end;
end;

// Show bitmap when selected in open dialogue - be graceful if there's an error
procedure TForm1.OpenDialog1SelectionChange(Sender: TObject);
begin
  try
    Image1.Picture.Bitmap.LoadFromFile(OpenDialog1.Filename);
  except
  end;
end;

// Load bitmap from file
procedure TForm1.OpenButtonClick(Sender: TObject);
begin
  if OpenDialog1.Execute then begin
    Image1.Picture.Bitmap.LoadFromFile(OpenDialog1.Filename);
    SaveDialog1.InitialDir:=ExtractFilePath(OpenDialog1.Filename);
    UpdateMask;
    CheckSize;
  end;
end;

procedure TForm1.PasteButtonClick(Sender: TObject);
begin
  try
    Image1.Picture.Bitmap.Assign(Clipboard);
    UpdateMask;
    CheckSize;
  except
  end;
end;

procedure TForm1.SaveButtonClick(Sender: TObject);
begin
  if SaveDialog1.Execute then Memo1.Lines.SaveToFile(SaveDialog1.Filename);
end;

procedure TForm1.CopyButtonClick(Sender: TObject);
begin
  Memo1.SelectAll;
  Memo1.CopyToClipboard;
  Memo1.SelStart:=0;
  Memo1.SelLength:=0;
end;

procedure TForm1.TestButtonClick(Sender: TObject);
var
  CopyOfRegion,TempRgn:HRgn;
begin
  // I must give Windows a copy of my region since it takes it away
  // and I can't use it any more
  if TestButton.Down then begin
    CopyOfRegion:=CreateRectRgn(0,0,0,0);
    CombineRgn(CopyOfRegion,CopyOfRegion,MyRgn,rgn_or); // copy region
    // Manipulate region so it covers the right bit
    TempRgn:=CreateRectRgn(-4,-4,279,120);
    CombineRgn(CopyOfRegion,CopyOfRegion,TempRgn,rgn_xor);
    DeleteObject(TempRgn);
    OffsetRgn(CopyOfRegion,Panel2.Left+Image1.Left+GetSystemMetrics(SM_CXFRAME),Panel2.Top+Image1.Top+GetSystemMetrics(SM_CYFRAME)+GetSystemMetrics(SM_CYCAPTION));
    TempRgn:=CreateRectRgnIndirect(Rect(0,0,form1.width,form1.height));
    CombineRgn(CopyOfRegion,CopyOfRegion,TempRgn,rgn_xor);
    DeleteObject(TempRgn);
    SetWindowRgn(form1.handle,CopyOfRegion,true);
  end else SetWindowRgn(form1.handle,0,true);
end;

procedure TForm1.AboutButtonClick(Sender: TObject);
begin
  Application.MessageBox(
    WindowTitle+#13+
    'by Maxim on 31/3/01'+#13+
    'maxim@mwos.cjb.net'+#13+
    'http://winamp.mwos.cjb.net'+#13#13+
    'To use:'+#13+
    '1. Open or paste image.'+#13+
    '2. Choose transparent colour by clicking on it.'+#13+
    '3. Choose which window and state it is.'+#13+
    '4. Click on Go.'+#13+
    '5. Save or copy generated text.',
    'Info/help',mb_iconinformation
  );
end;

end.
