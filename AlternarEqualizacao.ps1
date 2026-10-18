# Executar no Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'

trap {
 $detalhes = $_.Exception.ToString() +
  "`r`n`r`nLocal no script:`r`n" +
  $_.ScriptStackTrace

 $caminho = Join-Path $PSScriptRoot 'ErroDetalhado.txt'

 [IO.File]::WriteAllText(
  $caminho,
  $detalhes,
  [Text.Encoding]::UTF8
 )

 Write-Host "Erro registrado em: $caminho" -ForegroundColor Yellow
 exit 1
}

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms

# Inicializar a automacao atraves de uma chamada C#.
$referenciasUIA = @(
 [System.Windows.Automation.AutomationElement].Assembly.Location
 [System.Windows.Automation.AutomationProperty].Assembly.Location
) | Select-Object -Unique

Add-Type -ReferencedAssemblies $referenciasUIA -TypeDefinition @'
using System.Windows.Automation;

public static class InicializadorUIA
{
    [System.Runtime.CompilerServices.MethodImpl(
        System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
    public static void Iniciar()
    {
        ClientSettings.RegisterClientSideProviders(
            new ClientSideProviderDescription[0]
        );
    }
}
'@

[InicializadorUIA]::Iniciar()

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class AudioPadrao {
 [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
 class Enumerator {}

 [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface IEnum {
  void EnumAudioEndpoints();
  void GetDefaultAudioEndpoint(int flow, int role, out IDevice device);
 }

 [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface IDevice {
  void Activate();
  void OpenPropertyStore(int access, out IStore store);
  void GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
 }

 [StructLayout(LayoutKind.Sequential)]
 struct Key {
  public Guid guid;
  public uint pid;
 }

 [StructLayout(LayoutKind.Explicit, Size=24)]
 struct Value {
  [FieldOffset(0)] public ushort type;
  [FieldOffset(8)] public IntPtr text;
 }

 [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface IStore {
  void GetCount(out uint count);
  void GetAt(uint index, out Key key);
  void GetValue(ref Key key, out Value value);
 }

 [DllImport("ole32.dll")]
 static extern int PropVariantClear(ref Value value);

 [DllImport("user32.dll")]
 static extern IntPtr SendMessageTimeout(
  IntPtr h, uint m, IntPtr w, IntPtr l,
  uint flags, uint ms, out IntPtr result
 );

 public static void Close(int handle) {
  IntPtr result;
  SendMessageTimeout(
   new IntPtr(handle), 0x10, IntPtr.Zero,
   IntPtr.Zero, 2, 500, out result
  );
 }

 static string Read(IStore store, string guid, uint pid) {
  Key key = new Key { guid = new Guid(guid), pid = pid };
  Value v;
  store.GetValue(ref key, out v);

  try {
   return v.type == 31 ? Marshal.PtrToStringUni(v.text) : "";
  }
  finally {
   PropVariantClear(ref v);
  }
 }

 public static string[] Get() {
  IEnum e = (IEnum)new Enumerator();
  IDevice d = null;
  IStore s = null;

  try {
   // Reproducao; dispositivo padrao comum, nao de comunicacoes.
   e.GetDefaultAudioEndpoint(0, 0, out d);

   string id;
   d.GetId(out id);
   d.OpenPropertyStore(0, out s);

   return new string[] {
    id,
    Read(s, "A45C254E-DF1C-4EFD-8020-67D146A850E0", 2),
    Read(s, "026E516E-B814-414B-83CD-856D6FEF4822", 2)
   };
  }
  finally {
   if (s != null) Marshal.ReleaseComObject(s);
   if (d != null) Marshal.ReleaseComObject(d);
   Marshal.ReleaseComObject(e);
  }
 }
}
'@

Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class JanelasSom
{
    [DllImport("user32.dll")]
    static extern IntPtr GetParent(IntPtr janela);

    [DllImport("user32.dll")]
    static extern int GetDlgCtrlID(IntPtr janela);

    [DllImport("user32.dll")]
    static extern bool IsWindowEnabled(IntPtr janela);

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool PostMessage(
        IntPtr janela, uint mensagem, IntPtr wParam, IntPtr lParam
    );

    public static void AbrirPropriedades(int handle)
    {
        IntPtr botao = new IntPtr(handle);

        if (handle == 0 ||
            GetDlgCtrlID(botao) != 1003 ||
            !IsWindowEnabled(botao))
        {
            throw new InvalidOperationException(
                "Botao Propriedades nao identificado com seguranca."
            );
        }

        IntPtr destino = GetParent(botao);

        if (destino == IntPtr.Zero)
        {
            throw new InvalidOperationException(
                "Janela do botao Propriedades nao encontrada."
            );
        }

        // WM_COMMAND / BN_CLICKED: abrir sem aguardar a janela modal.
        if (!PostMessage(destino, 0x0111, new IntPtr(1003), botao))
        {
            throw new System.ComponentModel.Win32Exception(
                Marshal.GetLastWin32Error()
            );
        }
    }
    delegate bool Enumerador(IntPtr janela, IntPtr parametro);

    [DllImport("user32.dll")]
    static extern bool EnumWindows(Enumerador callback, IntPtr parametro);

    [DllImport("user32.dll")]
    static extern bool IsWindowVisible(IntPtr janela);

    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(IntPtr janela, out uint processo);

    [DllImport("user32.dll")]
    static extern IntPtr GetWindow(IntPtr janela, uint comando);

    public static int[] Buscar(int processo, int principal)
    {
        var resultado = new List<int>();
        IntPtr janelaPrincipal = new IntPtr(principal);

        EnumWindows(delegate(IntPtr janela, IntPtr parametro)
        {
            if (!IsWindowVisible(janela))
                return true;

            uint pid;
            GetWindowThreadProcessId(janela, out pid);
            bool incluir = pid == (uint)processo;

            if (!incluir && principal != 0)
            {
                IntPtr dona = GetWindow(janela, 4);

                for (int i = 0; dona != IntPtr.Zero && i < 32; i++)
                {
                    if (dona == janelaPrincipal)
                    {
                        incluir = true;
                        break;
                    }

                    dona = GetWindow(dona, 4);
                }
            }

            if (incluir)
                resultado.Add(unchecked((int)janela.ToInt64()));

            return true;
        }, IntPtr.Zero);

        return resultado.ToArray();
    }
}
'@

$AE = [System.Windows.Automation.AutomationElement]
$CT = [System.Windows.Automation.ControlType]
$TS = [System.Windows.Automation.TreeScope]
$TP = [System.Windows.Automation.TogglePattern]
$SP = [System.Windows.Automation.SelectionItemPattern]
$IP = [System.Windows.Automation.InvokePattern]
$Off = [System.Windows.Automation.ToggleState]::Off
$On = [System.Windows.Automation.ToggleState]::On

function Normalizar([string]$s) {
 $s = $s.Normalize([Text.NormalizationForm]::FormD)
 ([regex]::Replace($s, '\p{M}', '') -replace '&','').ToLowerInvariant().Trim()
}

function Elementos($raiz, $tipo) {
 $cond = New-Object System.Windows.Automation.PropertyCondition(
  $AE::ControlTypeProperty, $tipo
 )
 $raiz.FindAll($TS::Descendants, $cond)
}

function Todos($raiz) {
 $raiz.FindAll(
  $TS::Descendants,
  [System.Windows.Automation.Condition]::TrueCondition
 )
}

function Exato($raiz, $tipo, [string[]]$nomes) {
 Elementos $raiz $tipo | Where-Object {
  (Normalizar $_.Current.Name) -in $nomes
 }
}

function Esperar([scriptblock]$consulta, [string]$erro) {
 $tempo = [Diagnostics.Stopwatch]::StartNew()
 do {
  $achado = @(& $consulta)
  if ($achado.Count -eq 1) { return $achado[0] }
  if ($achado.Count -gt 1) {
   throw "Identificacao ambigua: $erro"
  }
  Start-Sleep -Milliseconds 80
 } while ($tempo.ElapsedMilliseconds -lt 4000)
 throw $erro
}

function Acionar($e) {
 if (-not $e.Current.IsEnabled) {
  throw 'Controle desabilitado; operacao cancelada.'
 }
 $e.GetCurrentPattern($IP::Pattern).Invoke()
}

function Janelas {
 $principal = 0

 if ($null -ne $script:janela) {
  $principal = $script:janela.Current.NativeWindowHandle
 }

 foreach ($handle in [JanelasSom]::Buscar(
  $script:processo.Id, $principal
 )) {
  try {
   $AE::FromHandle([IntPtr]::new($handle))
  }
  catch {
   # A janela pode ter fechado durante a enumeracao.
  }
 }
}

function Estado($e) {
 $e.GetCurrentPattern($TP::Pattern).Current.ToggleState
}

function Instantaneo($raiz) {
 $estados = @{}
 foreach ($e in (Todos $raiz)) {
  $padrao = $null
  if ($e.TryGetCurrentPattern($TP::Pattern, [ref]$padrao)) {
   $estados[($e.GetRuntimeId() -join ',')] = $padrao.Current.ToggleState
  }
 }
 return $estados
}

function NotificarLoudness([bool]$ativado) {
 $appId = 'LoudnessEqualization.Notifications'
 $programas = [Environment]::GetFolderPath('Programs')
 $atalho = Join-Path $programas 'Loudness Equalization.lnk'

 # Registrar a identidade usando um atalho do menu Iniciar.
 if (-not (Test-Path -LiteralPath $atalho)) {
  if (-not ('IdentidadeLoudness' -as [type])) {
   Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class IdentidadeLoudness
{
    [StructLayout(LayoutKind.Sequential)]
    struct Chave
    {
        public Guid formato;
        public uint numero;
    }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    struct Valor
    {
        [FieldOffset(0)] public ushort tipo;
        [FieldOffset(8)] public IntPtr texto;
    }

    [ComImport]
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropriedades
    {
        void GetCount(out uint quantidade);
        void GetAt(uint indice, out Chave chave);
        void GetValue(ref Chave chave, out Valor valor);
        void SetValue(ref Chave chave, ref Valor valor);
        void Commit();
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode,
        PreserveSig = false)]
    static extern void SHGetPropertyStoreFromParsingName(
        string caminho, IntPtr contexto, uint flags,
        ref Guid interfaceId, out IPropriedades propriedades);

    public static void Registrar(string caminho, string appId)
    {
        Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
        IPropriedades propriedades = null;
        Valor valor = new Valor();

        try
        {
            SHGetPropertyStoreFromParsingName(
                caminho, IntPtr.Zero, 2, ref iid, out propriedades);

            Chave chave = new Chave {
                formato = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
                numero = 5
            };

            valor.tipo = 31;
            valor.texto = Marshal.StringToCoTaskMemUni(appId);

            propriedades.SetValue(ref chave, ref valor);
            propriedades.Commit();
        }
        finally
        {
            if (valor.texto != IntPtr.Zero)
                Marshal.FreeCoTaskMem(valor.texto);

            if (propriedades != null)
                Marshal.ReleaseComObject(propriedades);
        }
    }
}
'@
  }

  $shell = New-Object -ComObject WScript.Shell
  $link = $shell.CreateShortcut($atalho)
  $link.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
  $link.Arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
  $link.WorkingDirectory = $PSScriptRoot
  $link.Description = 'Alternar Loudness Equalization'
  $link.Save()

  try {
   [IdentidadeLoudness]::Registrar($atalho, $appId)
  }
  catch {
   Remove-Item -LiteralPath $atalho -ErrorAction SilentlyContinue
   throw
  }
  finally {
   [void][Runtime.InteropServices.Marshal]::ReleaseComObject($link)
   [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
  }
 }

 # Nome apresentado nas configuracoes de notificacoes.
 $registro = "HKCU:\Software\Classes\AppUserModelId\$appId"
 New-Item -Path $registro -Force | Out-Null
 New-ItemProperty -Path $registro -Name 'DisplayName' `
  -Value 'Loudness Equalization' -PropertyType String -Force | Out-Null

 Add-Type -AssemblyName System.Runtime.WindowsRuntime

 [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
 [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
 [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

 $estado = 'OFF'
 if ($ativado) { $estado = 'ON' }

 $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
 $xml.LoadXml(@"
<toast duration="short">
 <visual>
  <binding template="ToastGeneric">
   <text>Loudness Equalization $estado</text>
  </binding>
 </visual>
 <audio silent="true"/>
</toast>
"@)

 $notificacao = [Windows.UI.Notifications.ToastNotification]::new($xml)
 $notificacao.ExpirationTime = [DateTimeOffset]::Now.AddSeconds(10)
 $emissor = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId)

 $emissor.Show($notificacao)
}

$falha = $null
$estadoNotificacao = $null
$janela = $null
$propriedades = $null
$processo = $null
$travado = $false

$mutex = New-Object Threading.Mutex(
 $false, 'Local\AlternarSomenteLoudnessEqualization'
)

try {
 $travado = $mutex.WaitOne(0)
 if (-not $travado) {
  throw 'Ja existe uma execucao em andamento.'
 }

 $dispositivo = [AudioPadrao]::Get()
 if (-not $dispositivo[1] -or -not $dispositivo[2]) {
  throw 'O driver nao informou os nomes necessarios para identificar o dispositivo com seguranca.'
 }

 $descricao = Normalizar $dispositivo[1]
 $interface = Normalizar $dispositivo[2]

 $processo = Start-Process "$env:WINDIR\System32\rundll32.exe" `
  -ArgumentList 'shell32.dll,Control_RunDLL mmsys.cpl,,0' -PassThru

 $janela = Esperar { Janelas } `
  'A janela Som nao abriu em um processo proprio. Feche as configuracoes de Som e tente novamente.'

 $item = Esperar {
  Elementos $janela $CT::ListItem | Where-Object {
   (Normalizar $_.Current.Name) -eq $descricao
  }
 } 'Nao foi possivel identificar um unico dispositivo com o nome do dispositivo padrao.' 

 $selecao = $item.GetCurrentPattern($SP::Pattern)
 $selecao.Select()
 if (-not $selecao.Current.IsSelected) {
  throw 'A selecao do dispositivo nao foi confirmada.'
 }

 $botao = Esperar {
  Exato $janela $CT::Button @('propriedades','properties')
 } 'Botao Propriedades nao encontrado.'

  [JanelasSom]::AbrirPropriedades($botao.Current.NativeWindowHandle)

 $propriedades = Esperar {
  Janelas | Where-Object {
   $_.Current.NativeWindowHandle -ne $janela.Current.NativeWindowHandle
  }
 } 'Janela de propriedades nao encontrada.'

 $aba = Esperar {
  Exato $propriedades $CT::TabItem @('aprimoramentos','enhancements')
 } 'Este driver nao expoe a aba Aprimoramentos compativel.'

 $aba.GetCurrentPattern($SP::Pattern).Select()

 $opcao = Esperar {
  Todos $propriedades | Where-Object {
   (Normalizar $_.Current.Name) -in @(
    'equalizacao de intensidade','loudness equalization'
   ) -and $_.Current.ControlType -in @($CT::CheckBox, $CT::ListItem)
  }
 } 'Equalizacao de Intensidade nao encontrada ou nao acessivel neste driver.'

 if (-not $opcao.Current.IsEnabled) {
  throw 'Equalizacao de Intensidade desabilitada pelo driver; nenhuma alteracao.'
 }

 # Nao habilitar o interruptor geral de aprimoramentos.
 foreach ($e in (Exato $propriedades $CT::CheckBox @(
  'desabilitar todos os aprimoramentos',
  'disable all enhancements',
  'disable all sound effects'
 ))) {
  if ((Estado $e) -ne $Off) {
   throw 'Todos os aprimoramentos estao desabilitados. O script nao alterara o interruptor geral.'
  }
 }

 $ok = @(Elementos $propriedades $CT::Button | Where-Object {
  $_.Current.AutomationId -eq '1'
 })
 if ($ok.Count -ne 1 -or -not $ok[0].Current.IsEnabled) {
  throw 'Botao OK nao identificado com seguranca.'
 }

 $antes = Instantaneo $propriedades
 $chave = $opcao.GetRuntimeId() -join ','

 if (-not $antes.ContainsKey($chave)) {
  throw 'O driver nao permite alternar esta caixa pela interface de acessibilidade.'
 }

 $original = $antes[$chave]
 if ($original -eq [System.Windows.Automation.ToggleState]::Indeterminate) {
  throw 'Estado da opcao indefinido.'
 }

 if (([AudioPadrao]::Get())[0] -ne $dispositivo[0]) {
  throw 'O dispositivo padrao mudou; operacao cancelada.'
 }

 # Unica modificacao de audio solicitada pelo programa.
 $opcao.GetCurrentPattern($TP::Pattern).Toggle()

 $depois = Instantaneo $propriedades
 if ($depois.Count -ne $antes.Count) {
  throw 'A interface mudou inesperadamente; cancelando sem aplicar.'
 }

  # Identificar a linha que contem a caixa da Equalizacao.
 $paiDaOpcao = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent(
  $opcao
 )

 $idPaiDaOpcao = $null

 if ($null -ne $paiDaOpcao) {
  if (
   $paiDaOpcao.Current.ControlType -eq $CT::DataItem -and
   (Normalizar $paiDaOpcao.Current.Name) -eq
   (Normalizar $opcao.Current.Name)
  ) {
   $idPaiDaOpcao = $paiDaOpcao.GetRuntimeId() -join ','
  }
 }

 foreach ($k in $antes.Keys) {
  if (-not $depois.ContainsKey($k)) {
   throw 'A interface mudou inesperadamente; cancelando sem aplicar.'
  }

  if ($k -ne $chave -and $depois[$k] -ne $antes[$k]) {
   # Aceitar somente a linha pai espelhando a mesma caixa.
   $mesmaOpcao = (
    $k -eq $idPaiDaOpcao -and
    $antes[$k] -eq $antes[$chave] -and
    $depois[$k] -eq $depois[$chave]
   )

   if (-not $mesmaOpcao) {
    throw 'Outro aprimoramento mudou junto. Cancelando sem aplicar.'
   }
  }
 }

 $esperado = $On
 if ($original -eq $On) { $esperado = $Off }
 if ($depois[$chave] -ne $esperado) {
  throw 'Nao foi possivel confirmar a alternancia; cancelando sem aplicar.'
 }

 if (([AudioPadrao]::Get())[0] -ne $dispositivo[0]) {
  throw 'O dispositivo padrao mudou; cancelando sem aplicar.'
 }

 # OK salva e fecha, equivalendo a Aplicar + OK.
 $handlePropriedades = $propriedades.Current.NativeWindowHandle
 Acionar $ok[0]

 $limite = [Diagnostics.Stopwatch]::StartNew()
 while (@(Janelas | Where-Object {
  $_.Current.NativeWindowHandle -eq $handlePropriedades
 }).Count -gt 0) {
  if ($limite.ElapsedMilliseconds -gt 3000) {
   throw 'O driver nao confirmou o fechamento. Verifique o estado da opcao.'
  }
  Start-Sleep -Milliseconds 80
 }
  $propriedades = $null
 $estadoNotificacao = ($esperado -eq $On)
}
catch {
 $falha = $_.Exception.Message
}
finally {
 # Fechar propriedades cancela alteracoes ainda nao aplicadas.
 if ($null -ne $propriedades) {
  try {
   [AudioPadrao]::Close($propriedades.Current.NativeWindowHandle)
  } catch {}
 }
 if ($null -ne $janela) {
  try {
   [AudioPadrao]::Close($janela.Current.NativeWindowHandle)
  } catch {}
 }
 if ($travado) { $mutex.ReleaseMutex() }
 $mutex.Dispose()
}

if ($falha) {
 [System.Windows.Forms.MessageBox]::Show(
  $falha, 'Equalizacao de Intensidade', 'OK', 'Information'
 ) | Out-Null
}

if (-not $falha -and $null -ne $estadoNotificacao) {
 try {
  NotificarLoudness -ativado $estadoNotificacao
 }
 catch {
  Write-Warning (
   'A alteracao de audio foi concluida, mas a notificacao falhou: ' +
   $_.Exception.Message
  )
 }
}