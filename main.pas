unit main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  SynEdit;

type

  { TfrmMain }

  TfrmMain = class(TForm)
    BtnConnect: TButton;
    EdtIpPort: TEdit;
    fbtnpanel: TPanel;
    procedure BtnConnectClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure EdtIpPortKeyDown(Sender: TObject; var Key: Word;Shift: TShiftState);
    procedure SetBtnMode(mode:Boolean);
    procedure FormCreate(Sender: TObject);
  private

  public
    procedure ReadIniFile;
    procedure WriteIniFile;
    procedure OnIdleUpdate(Sender:TObject;var Done:Boolean);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

{ TfrmMain }

uses
 windows,
 winsock2,
 g_bufstream,
 LineStream,
 synlog,
 SynEditLineStream,
 LazSynEditText,
 SynEditMarkupBracket,
 sockets,
 IniFiles;

var
 FIniFile:TIniFile;

 FLogFile:RawByteString='log.txt';

 FAddHandle:THandle;
 FGetHandle:THandle;

 FFile:TStream;
 FList:TSynEditLineStream;

 FThread:TThreadID=0;

 FUpdate:Integer=0;
 FCancel:Integer=0;
 FThStop:Integer=0;

type
 TMySynLog=class(TCustomSynLog)
  function LinesCreate:TSynEditStringListBase; override;
 end;

function TMySynLog.LinesCreate:TSynEditStringListBase;
begin
 FList:=TSynEditLineStream.Create;

 FList.FSynLog:=Self;
 FList.FStream:=TLineStream.Create(FFile);

 Result:=FList;
end;

var
 mlog:TMySynLog;

procedure TfrmMain.ReadIniFile;
begin
 FLogFile      :=Trim(FIniFile.ReadString('main','LogFile',Trim(FLogFile)));
 EdtIpPort.Text:=Trim(FIniFile.ReadString('main','IpPort' ,Trim(EdtIpPort.Text)));
end;

procedure TfrmMain.WriteIniFile;
begin
 FIniFile.WriteString('main','LogFile',Trim(FLogFile));
 FIniFile.WriteString('main','IpPort' ,Trim(EdtIpPort.Text));
end;

procedure TfrmMain.FormCreate(Sender: TObject);
var
 FLogFileW:WideString;
begin
 FIniFile:=TIniFile.Create('fpnetlog.ini');

 ReadIniFile;

 FLogFileW:=UTF8Decode(FLogFile);

 FAddHandle:=CreateFileW(PWideChar(FLogFileW),
                         GENERIC_READ or GENERIC_WRITE,
                         FILE_SHARE_READ,
                         nil,
                         OPEN_ALWAYS,
                         0,
                         0);

 FGetHandle:=CreateFileW(PWideChar(FLogFileW),
                         GENERIC_READ,
                         FILE_SHARE_READ or FILE_SHARE_WRITE,
                         nil,
                         OPEN_EXISTING,
                         0,
                         0);

 FileSeek(FAddHandle,0,fsFromEnd);

 FFile:=TBufferedFileStream.Create(FGetHandle);

 mlog:=TMySynLog.Create(Self);
 mlog.Parent:=Self;

 mlog.AnchorClient(0);

 mlog.Anchors:=[akTop, akLeft, akRight, akBottom];

 mlog.AnchorSide[akTop].Control:=fbtnpanel;
 mlog.AnchorSide[akTop].Side   :=asrBottom;

 mlog.BracketHighlightStyle:=sbhsBoth;

 mlog.Font.Style:=[];

 Application.AddOnIdleHandler(@OnIdleUpdate,False);
end;

procedure TfrmMain.OnIdleUpdate(Sender:TObject;var Done:Boolean);
begin
 Done:=True;

 if (System.InterlockedExchange(FUpdate,0)<>0) then
 if (FList<>nil) then
 begin
  FList.Update;
 end;

 if (System.InterlockedExchange(FThStop,0)<>0) then
 begin
  CloseThread(FThread);
  FThread:=0;
  //
  SetBtnMode(True);
 end;
end;

function ParseSockaddr(const S:RawByteString;var addr:sockaddr_in):Boolean;
var
 i:Integer;
 ip4:in_addr;
 A:RawByteString;
 P:RawByteString;
begin
 Result:=False;

 addr:=Default(sockaddr_in);
 addr.sin_family:=AF_INET;

 i:=Pos(':',S);
 if (i=0) then Exit;

 A:=Copy(S,1,i-1);
 P:=Copy(S,i+1);

 ip4:=Default(in_addr);
 if not TryStrToHostAddr(A, ip4) then Exit;

 addr.sin_addr.s_addr:=htonl(ip4.s_addr);

 i:=0;
 if not TryStrToInt(P,i) then Exit;

 addr.sin_port:=htons(i);

 Result:=True;
end;

function connect_thread(parameter:pointer):ptrint; forward;

procedure TfrmMain.BtnConnectClick(Sender: TObject);
var
 i,c:Integer;
 addr:sockaddr_in;
 ptr:psockaddr_in;
begin

 addr:=Default(sockaddr_in);
 if not ParseSockaddr(EdtIpPort.Text,addr) then
 begin
  ShowMessage('Incorrect addres:'+EdtIpPort.Text);
 end;

 WriteIniFile;

 mlog.TopLine:=-1;

 i:=mlog.LinesInWindow;
 c:=FList.GetCount;

 if (c>i) then
 begin
  c:=c-i+1;
 end;

 mlog.TopLine:=c;

 ptr:=AllocMem(SizeOf(sockaddr_in));
 ptr^:=addr;

 FCancel:=0;
 FThStop:=0;

 SetBtnMode(False);

 FThread:=BeginThread(@connect_thread,ptr);
end;

procedure TfrmMain.BtnCloseClick(Sender: TObject);
begin
 System.InterlockedExchange(FCancel,1);
end;

procedure TfrmMain.EdtIpPortKeyDown(Sender: TObject; var Key: Word;Shift: TShiftState);
begin
 if (Key=13) then
 if (BtnConnect.OnClick=@BtnConnectClick) then
 begin
  BtnConnectClick(Sender);
 end;
end;

procedure TfrmMain.SetBtnMode(mode:Boolean);
begin
 case mode of
  True :
   begin
    BtnConnect.AutoSize:=False;
    BtnConnect.Caption:='Connect';
    BtnConnect.OnClick:=@BtnConnectClick;
   end;
  False:
   begin
    BtnConnect.AutoSize:=False;
    BtnConnect.Caption:='Close';
    BtnConnect.OnClick:=@BtnCloseClick;
   end;
 end;
end;

procedure WakeMainThread;
begin
 if Assigned(Classes.WakeMainThread) then
 begin
  Classes.WakeMainThread(nil);
 end;
end;

function LogWrite(ptr:Pointer;len:Longint):Longint;
begin
 Result:=FileWrite(FAddHandle,ptr^,len);

 System.InterlockedIncrement(FUpdate);

 WakeMainThread;
end;

function LogWrite(const S:RawByteString):Longint;
begin
 Result:=LogWrite(PChar(S),Length(S));
end;

function LogWriteln(const S:RawByteString):Longint;
begin
 Result:=LogWrite(S+#13#10);
end;

function set_blocking_mode(socket:Integer;is_blocking:Boolean):Integer;
var
 flags:DWord;
begin
 case is_blocking of
  True :flags:=0;
  False:flags:=1;
 end;

 Result:=ioctlsocket(socket,Integer(FIONBIO),@flags);
end;

function connect_thread(parameter:pointer):ptrint;
label
 _error;
var
 addr:sockaddr_in;
 s,err:Integer;
 tick:Int64;

 buf:array[0..1023] of AnsiChar;
 len:ssize_t;
begin
 Result:=0;
 if (parameter=nil) then Exit;
 addr:=psockaddr_in(parameter)^;
 FreeMem(parameter);

 s:=fpSocket(AF_INET, SOCK_STREAM, 0);

 if (s=-1) then
 begin
  LogWriteln('Internal Error:'+IntToStr(socketerror));
  goto _error;
 end;

 err:=set_blocking_mode(s,False);
 if (err<>0) then
 begin
  LogWriteln('Set nonblocking Error:'+IntToStr(socketerror));
  goto _error;
 end;

 tick:=GetTickCount64;
 repeat
  err:=fpconnect(s,@addr,SizeOf(addr));
  if (err=0) then Break;
  case socketerror of
   WSAEWOULDBLOCK:; //try again
   WSAEALREADY:;//in progress
   WSAEISCONN:
     begin
      err:=0;
      Break;
     end
   else
    begin
     LogWriteln('Connect Error:'+IntToStr(socketerror));
     goto _error;
    end;
  end;

  if ((GetTickCount64-tick)>3000) then //3s
  begin
   LogWriteln('Connect timeout to '+NetAddrToStr(addr.sin_addr)+':'+IntToStr(ntohs(addr.sin_port)));
   goto _error;
  end;

  if (FCancel<>0) then
  begin
   goto _error;
  end;

  Sleep(100);
 until false;

 LogWriteln('Connect to '+NetAddrToStr(addr.sin_addr)+':'+IntToStr(ntohs(addr.sin_port)));

 repeat
  len:=fprecv(s,@buf,SizeOf(buf),0);

  if (len=0) then
  begin
   Break;
  end else
  if (len<0) then
  begin
   if (socketerror<>WSAEWOULDBLOCK) then
   begin
    LogWriteln('fprecv Error:'+IntToStr(len)+':'+IntToStr(socketerror));
    Break;
   end;
   Sleep(100);
  end else
  begin
   LogWrite(@buf,len);
  end;

  if (FCancel<>0) then
  begin
   Break;
  end;

 until false;

 LogWriteln('Connect closed '+NetAddrToStr(addr.sin_addr)+':'+IntToStr(ntohs(addr.sin_port)));

 _error:

  if (s<>-1) then
  begin
   fpshutdown(s,2);
   CloseSocket(s);
  end;

  FThStop:=1;
  WakeMainThread;
end;


end.




