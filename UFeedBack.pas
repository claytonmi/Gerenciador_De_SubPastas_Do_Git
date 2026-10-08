unit UFeedBack;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.Buttons, System.DateUtils, System.JSON, System.Net.HttpClient,
  System.Net.URLClient, ShellAPI, Registry, System.RegularExpressions,
  System.IOUtils, UClasseValidacao;

type
  TFFormFeedBack = class(TForm)
    EditNome: TEdit;
    EditEmail: TEdit;
    EditAssunto: TEdit;
    MemoMensagem: TMemo;
    BtnEnviar: TBitBtn;
    BtnCancelar: TBitBtn;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    LabelMensagem: TLabel;
    LblStatus: TLabel;
    procedure BtnEnviarClick(Sender: TObject);
    procedure BtnCancelarClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure Logs();
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure EditEmailExit(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  FFormFeedBack: TFFormFeedBack;

implementation

{$R *.dfm}

procedure TFFormFeedBack.BtnCancelarClick(Sender: TObject);
begin
  EditNome.Clear;
  EditEmail.Clear;
  EditAssunto.Clear;
  MemoMensagem.Clear;
  BtnEnviar.Enabled := True;
  LblStatus.Caption := 'Pronto para enviar feedback.';
  Close;
end;

procedure SalvarUltimoEnvio;
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('\Software\GerenciadorDePastasGit\Feedback', True) then
      Reg.WriteString('UltimoEnvio', DateTimeToStr(Now));
  finally
    Reg.Free;
  end;
end;

function PodeEnviarFeedback: Boolean;
var
  Reg: TRegistry;
  UltimoEnvioStr: string;
  UltimoEnvio: TDateTime;
begin
  Result := True;
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('\Software\GerenciadorDePastasGit\Feedback') then
    begin
      UltimoEnvioStr := Reg.ReadString('UltimoEnvio');
      if TryStrToDateTime(UltimoEnvioStr, UltimoEnvio) then
        Result := MinutesBetween(Now, UltimoEnvio) >= 10;     // tempo permitido para próximo envio
    end;
  finally
    Reg.Free;
  end;
end;

function EmailValido(const Email: string): Boolean; forward;

function EnviarFeedbackParaScript(const Nome, Email, Assunto, Mensagem: string): Boolean;
const
  URL_API_FEEDBACK = 'https://script.google.com/macros/s/AKfycbzZG59eLhV4rifs1eJfrbEe20xsgyvFc7Xiv3wTA55yNZCZ6LWDHJwNPxxVUZzVj93UMQ/exec';
var
  ClienteHTTP: THTTPClient;
  CorpoRequisicao, CorpoResposta: TStringStream;
  Cabecalhos: TNetHeaders;
  Resposta: IHTTPResponse;
  DadosFeedback: TJSONObject;
  RespostaJSON, IndicadorSucesso, ValorErro, ValorMensagem: TJSONValue;
  TextoResposta, MensagemErro: string;
begin
  Result := False;
  ClienteHTTP := THTTPClient.Create;
  DadosFeedback := TJSONObject.Create;
  CorpoRequisicao := nil;
  CorpoResposta := nil;
  RespostaJSON := nil;
  try
    DadosFeedback.AddPair('name', Nome);
    DadosFeedback.AddPair('email', Email);
    DadosFeedback.AddPair('subject', Assunto);
    DadosFeedback.AddPair('message', Mensagem);
    DadosFeedback.AddPair('system', 'Gerenciador de Pastas do Git');
    DadosFeedback.AddPair('website', '');
    CorpoRequisicao := TStringStream.Create(DadosFeedback.ToString, TEncoding.UTF8);
    CorpoResposta := TStringStream.Create('', TEncoding.UTF8);
    SetLength(Cabecalhos, 1);
    Cabecalhos[0] := TNameValuePair.Create('Content-Type', 'application/json');
    ClienteHTTP.ConnectionTimeout := 15000;
    ClienteHTTP.ResponseTimeout := 20000;
    ClienteHTTP.HandleRedirects := True;

    Resposta := ClienteHTTP.Post(URL_API_FEEDBACK, CorpoRequisicao,
      CorpoResposta, Cabecalhos);
    CorpoResposta.Position := 0;
    TextoResposta := Trim(CorpoResposta.DataString);

    if (Resposta.StatusCode < 200) or (Resposta.StatusCode >= 300) then
      raise Exception.CreateFmt('O servico de feedback retornou HTTP %d: %s',
        [Resposta.StatusCode, Copy(TextoResposta, 1, 500)]);

    RespostaJSON := TJSONObject.ParseJSONValue(TextoResposta);
    if not (RespostaJSON is TJSONObject) then
      raise Exception.Create('Resposta nao JSON do Apps Script: ' + Copy(TextoResposta, 1, 500));

    ValorErro := TJSONObject(RespostaJSON).GetValue('error');
    if (ValorErro <> nil) and (Trim(ValorErro.Value) <> '') and
       (not SameText(Trim(ValorErro.Value), 'false')) and
       (not SameText(Trim(ValorErro.Value), 'null')) then
      raise Exception.Create('Apps Script: ' + Copy(ValorErro.Value, 1, 500));

    IndicadorSucesso := TJSONObject(RespostaJSON).GetValue('ok');
    if IndicadorSucesso = nil then
      IndicadorSucesso := TJSONObject(RespostaJSON).GetValue('success');
    if IndicadorSucesso = nil then
      IndicadorSucesso := TJSONObject(RespostaJSON).GetValue('sucesso');
    if IndicadorSucesso = nil then
      IndicadorSucesso := TJSONObject(RespostaJSON).GetValue('status');
    if IndicadorSucesso = nil then
      IndicadorSucesso := TJSONObject(RespostaJSON).GetValue('result');
    if IndicadorSucesso = nil then
      IndicadorSucesso := TJSONObject(RespostaJSON).GetValue('resultado');

    if IndicadorSucesso <> nil then
    begin
      if SameText(IndicadorSucesso.Value, 'true') or
         SameText(IndicadorSucesso.Value, 'success') or
         SameText(IndicadorSucesso.Value, 'ok') or
         SameText(IndicadorSucesso.Value, 'sucesso') or
         SameText(IndicadorSucesso.Value, 'sent') or
         SameText(IndicadorSucesso.Value, 'enviado') then
      begin
        Result := True;
        Exit;
      end;
    end;

    ValorMensagem := TJSONObject(RespostaJSON).GetValue('message');
    if ValorMensagem = nil then
      ValorMensagem := TJSONObject(RespostaJSON).GetValue('mensagem');
    if ValorMensagem <> nil then
      MensagemErro := ValorMensagem.Value + sLineBreak +
        'Resposta do Apps Script: ' + Copy(TextoResposta, 1, 800)
    else
      MensagemErro := 'O Apps Script nao confirmou o envio. Resposta: ' +
        Copy(TextoResposta, 1, 800);
    raise Exception.Create(MensagemErro);
  finally
    RespostaJSON.Free;
    CorpoResposta.Free;
    CorpoRequisicao.Free;
    DadosFeedback.Free;
    ClienteHTTP.Free;
  end;
end;
procedure TFFormFeedBack.BtnEnviarClick(Sender: TObject);
begin
  if Trim(EditNome.Text) = '' then
  begin
    ShowMessage('Preencha o campo nome.');
    EditNome.SetFocus;
    Exit;
  end;
  if not EmailValido(Trim(EditEmail.Text)) then
  begin
    ShowMessage('Informe um e-mail de contato valido.');
    EditEmail.SetFocus;
    Exit;
  end;
  if Trim(EditAssunto.Text) = '' then
  begin
    ShowMessage('Preencha o campo assunto.');
    EditAssunto.SetFocus;
    Exit;
  end;
  if Trim(MemoMensagem.Text) = '' then
  begin
    ShowMessage('Preencha a mensagem do feedback.');
    MemoMensagem.SetFocus;
    Exit;
  end;

  if not PodeEnviarFeedback then
  begin
    LblStatus.Caption := 'Aguarde alguns minutos antes de enviar outro feedback.';
    ShowMessage(LblStatus.Caption);
    Exit;
  end;

  BtnEnviar.Enabled := False;
  try
    LblStatus.Caption := 'Enviando feedback...';
    try
      if not EnviarFeedbackParaScript(Trim(EditNome.Text), Trim(EditEmail.Text),
        Trim(EditAssunto.Text), MemoMensagem.Text) then
        raise Exception.Create('O Apps Script nao confirmou o envio.');
      SalvarUltimoEnvio;
      LblStatus.Caption := 'Feedback enviado com sucesso!';
      EditNome.Clear;
      EditEmail.Clear;
      EditAssunto.Clear;
      MemoMensagem.Clear;
    except
      on E: Exception do
      begin
        LblStatus.Caption := 'Nao foi possivel enviar o feedback.';
        ShowMessage('Erro ao enviar o feedback: ' + E.Message);
      end;
    end;
  finally
    BtnEnviar.Enabled := True;
  end;
end;
function EmailValido(const Email: string): Boolean;
const
  PadraoEmail = '^[\w\.-]+@[\w\.-]+\.\w{2,}$';
begin
  Result := TRegEx.IsMatch(Email, PadraoEmail);
end;

procedure TFFormFeedBack.EditEmailExit(Sender: TObject);
begin
   if not EmailValido(EditEmail.Text) then
  begin
    ShowMessage('E-mail inválido! Por favor, digite um e-mail válido.');
    EditEmail.SetFocus;
  end;
end;

procedure TFFormFeedBack.Logs();
var
  LogsDir, DataHoje, ArquivoLogAtual, FilePath: string;
  InfoArq: TSearchRec;
  Ret: Integer;
begin
  LogsDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'Logs');
  if not DirectoryExists(LogsDir) then
    ForceDirectories(LogsDir);

  DataHoje := FormatDateTime('dd-mm-yyyy', Now);

  Ret := FindFirst(PChar(TPath.Combine(LogsDir, 'cmd_git_*.log')), faAnyFile, InfoArq);
  if Ret = 0 then
  begin
    repeat
      if Pos(DataHoje, InfoArq.Name) = 0 then
      begin
        FilePath := TPath.Combine(LogsDir, InfoArq.Name);
        if FileExists(FilePath) then
          DeleteFile(FilePath);
      end;
      Ret := FindNext(InfoArq);
    until Ret <> 0;
    FindClose(InfoArq);
  end;

  ArquivoLogAtual := Format('cmd_git_%s.log', [FormatDateTime('dd-mm-yyyy_hh-nn-ss', Now)]);
  ArquivoLogAtual := TPath.Combine(LogsDir, ArquivoLogAtual);

  UClasseValidacao.ArquivoLogGlobal := ArquivoLogAtual;
end;

procedure TFFormFeedBack.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  EditNome.Clear;
  EditEmail.Clear;
  EditAssunto.Clear;
  MemoMensagem.Clear;
  BtnEnviar.Enabled := True;
  LblStatus.Caption := 'Pronto para enviar feedback.';
end;

procedure TFFormFeedBack.FormCreate(Sender: TObject);
begin
  EditNome.Clear;
  EditEmail.Clear;
  EditAssunto.Clear;
  MemoMensagem.Clear;
  BtnEnviar.Enabled := True;
  LblStatus.Caption := 'Pronto para enviar feedback.';
end;

end.

