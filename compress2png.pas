unit compress2png;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, GraphType, IntfGraphics, FPImage, zstream;


function CompressToPNG(Data: PByteArray; DataSize: Integer; OutputFile: ansistring; MaxWidth: Integer = 4096): Boolean;

implementation

const
  ByteDepth = 1;

function CompressToPNG(Data: PByteArray; DataSize: Integer; OutputFile: ansistring; MaxWidth: Integer): Boolean;
var
  i, width, height: Integer;
  c: TFPColor;
  pic: TLazIntfImage;
  lRawImage: TRawImage;
  pngWriter: TLazWriterPNG;

  function feek(input: Byte): Word;
  begin
    result:=input * $100;
  end;

begin
  result:=False;

  height:=1;
  while DataSize div Height > MaxWidth do height:=Height + 1;
  width:=DataSize div Height;

  while DataSize > width*height do Inc(Height);

  lRawImage.Init;
  lRawImage.Description.Init_BPP24_B8G8R8_M1_BIO_TTB (width, Height);
  lRawImage.Description.BitsPerPixel:=32;
  lRawImage.Description.AlphaPrec:=8;
  lRawImage.Description.BluePrec:=8;
  lRawImage.Description.RedPrec:=8;
  lRawImage.Description.BluePrec:=8;
  lRawImage.CreateData(True);

  pic:=TLazIntfImage.Create(0, 0);
  pic.SetRawImage(lRawImage);
  for i:=0 to DataSize - 1 do
  begin
    //for j:=ByteDepth-1 downto 0 do
    //cc:=cc*$100 + data[i * ByteDepth + j];

    c.red   :=feek(data^[i * ByteDepth + 0]);
    c.green :=feek(data^[i * ByteDepth + 0]);
    c.blue  :=feek(data^[i * ByteDepth + 0]);
    c.alpha :=feek(255);
    pic.Colors[i mod width, i div width]:=c;
  end;
  c:=TColorToFPColor(0);
  c.red   :=feek(255);
  c.green :=feek(255);
  c.blue  :=feek(255);
  c.alpha :=feek(255);
  for i:=DataSize to Width*height -1 do
  begin
    pic.Colors[i mod width, i div width]:=c;
  end;
  pngWriter:=TLazWriterPNG.create;
  pngWriter.CompressionLevel:=clmax;
  pngWriter.UseAlpha:=False;
  pngWriter.Indexed:=False;
  pngWriter.WordSized:=False;
  pngWriter.GrayScale:=True;
  pic.SaveToFile(OutputFile, pngWriter);
  pngWriter.Free;
  (*
  with TPortableNetworkGraphic.Create do begin
        try
          LoadFromIntfImage(Pic);
          SaveToFile(OutputFile);
        finally
          Free;
        end;
      end; *)
  pic.Free;
end;

end.

