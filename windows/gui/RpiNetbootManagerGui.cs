using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;

namespace RpiNetbootWindowsGui
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm(ParseInitialTask(args), ParseAutoRun(args)));
        }

        private static string ParseInitialTask(string[] args)
        {
            if (args == null) return "status";
            for (int i = 0; i < args.Length; i++)
            {
                if (string.Equals(args[i], "--task", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
                {
                    return args[i + 1];
                }
                if (args[i].StartsWith("--task=", StringComparison.OrdinalIgnoreCase))
                {
                    return args[i].Substring("--task=".Length);
                }
            }
            return "status";
        }

        private static bool ParseAutoRun(string[] args)
        {
            if (args == null) return false;
            for (int i = 0; i < args.Length; i++)
            {
                if (string.Equals(args[i], "--run", StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
            return false;
        }
    }

    internal sealed class MainForm : Form
    {
        private readonly string projectRoot;
        private readonly string scriptPath;
        private readonly List<ActionDefinition> actions = new List<ActionDefinition>();

        private Panel sidebar;
        private FlowLayoutPanel navList;
        private Panel main;
        private Label pageTitle;
        private Label pageSubtitle;
        private Label statusLabel;
        private Label helpTitle;
        private TextBox helpBody;
        private TextBox taskTextBox;
        private TextBox logBox;
        private Button primaryButton;
        private Button secondaryButton;
        private ToolTip tips;
        private Process runningProcess;
        private bool isRunning;
        private string selectedTask = "status";
        private readonly bool autoRunInitialTask;

        private readonly Color bg = Color.FromArgb(245, 247, 248);
        private readonly Color ink = Color.FromArgb(26, 33, 30);
        private readonly Color muted = Color.FromArgb(95, 106, 101);
        private readonly Color sidebarBg = Color.FromArgb(24, 34, 31);
        private readonly Color sidebarMuted = Color.FromArgb(166, 177, 171);
        private readonly Color teal = Color.FromArgb(15, 118, 110);
        private readonly Color tealSoft = Color.FromArgb(220, 244, 239);
        private readonly Color amber = Color.FromArgb(190, 120, 32);
        private readonly Color cardBorder = Color.FromArgb(218, 224, 218);

        public MainForm(string initialTask, bool autoRun)
        {
            projectRoot = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            scriptPath = Path.Combine(projectRoot, "tools", "rpi-netboot-manager.ps1");
            autoRunInitialTask = autoRun;

            Text = "RPI 네트워크 부팅 관리자";
            AutoScaleMode = AutoScaleMode.Dpi;
            AutoScaleDimensions = new SizeF(96f, 96f);
            MinimumSize = new Size(1120, 760);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = bg;
            Font = new Font("Segoe UI", 9.5f, FontStyle.Regular);
            Icon = LoadAppIcon();
            tips = new ToolTip();
            tips.AutoPopDelay = 12000;
            tips.InitialDelay = 350;
            tips.ReshowDelay = 100;

            BuildActions();
            BuildUi();
            SelectTask(FindAction(initialTask) == null ? "status" : initialTask);
            if (autoRunInitialTask)
            {
                BeginInvoke(new Action(RunSelectedTask));
            }
        }

        private Icon LoadAppIcon()
        {
            string iconPath = Path.Combine(projectRoot, "gui", "rpi-netboot.ico");
            if (File.Exists(iconPath))
            {
                return new Icon(iconPath);
            }
            return SystemIcons.Application;
        }

        private void BuildActions()
        {
            actions.Add(new ActionDefinition("status", "상태 확인", "RPi4 네트워크 부팅 상태를 읽기 전용으로 확인합니다.", IconKind.Pulse, false));
            actions.Add(new ActionDefinition("server-setup", "서버 PC 자동 준비", "D: 저장소, 이더넷 10.73.0.10, 설정 파일, TFTP 동기화까지 정리합니다.", IconKind.Server, true));
            actions.Add(new ActionDefinition("lite-provider-start", "무료 부팅 서비스 시작", "내장 DHCP/TFTP 서버와 무료 WinNFSd를 시작합니다. haneWIN 평가판 없이 테스트할 기본 provider입니다.", IconKind.Network, true));
            actions.Add(new ActionDefinition("lite-provider-stop", "무료 부팅 서비스 중지", "내장 DHCP/TFTP 서버와 WinNFSd를 중지합니다. 테스트 종료나 포트 정리 때 사용합니다.", IconKind.Shield, true));
            actions.Add(new ActionDefinition("install-services", "haneWIN 평가판 설치", "haneWIN은 빠른 검증용 30일 평가판 provider입니다. 무료 provider가 안 될 때만 보조로 사용합니다.", IconKind.Package, true));
            actions.Add(new ActionDefinition("configure-services", "haneWIN 설정 적용", "haneWIN DHCP/TFTP/NFS를 이더넷 10.73.0.10, D:\\tftp, D:\\rootfs 값으로 맞춥니다.", IconKind.Sync, true));
            actions.Add(new ActionDefinition("prepare-sd", "RPi4 EEPROM SD 쓰기", "S: SD카드에 RPi4 Network Boot EEPROM 이미지를 씁니다.", IconKind.SdCard, true, true));
            actions.Add(new ActionDefinition("copy-boot", "RPi4 부팅파일 복사", "RPi4 OS boot 파티션 파일을 D:\\tftp\\<serial>로 복사합니다.", IconKind.SdCard, false));
            actions.Add(new ActionDefinition("rootfs-status", "rootfs 상태 확인", "D:\\rootfs\\<serial>에 init, bin, etc, usr가 있는지 확인합니다.", IconKind.Check, false));
            actions.Add(new ActionDefinition("rootfs-prepare", "rootfs 준비 안내 만들기", "Pi/Linux helper에서 실행할 rootfs 복제 스크립트와 안내문을 만듭니다.", IconKind.Doc, false));
            actions.Add(new ActionDefinition("zero2w-gadget-sd", "Zero 2 W gadget SD", "S: SD를 Zero 2 W USB Ethernet gadget 부팅용으로 패치합니다.", IconKind.SdCard, false, true));
            actions.Add(new ActionDefinition("verify", "전체 상태 다시 확인", "랩 상태와 TFTP 파일 무결성을 확인합니다. 네트워크 부팅 대상은 RPi4만입니다.", IconKind.Check, false));
            actions.Add(new ActionDefinition("sync-tftp", "TFTP 파일 복사/검증", "generated 파일을 D:\\tftp로 복사하고 cmdline/config 깨짐을 검사합니다.", IconKind.Sync, false));
            actions.Add(new ActionDefinition("firewall", "부팅 포트 방화벽 열기", "DHCP, TFTP, NFS, iSCSI에 필요한 Windows 방화벽 규칙을 추가합니다.", IconKind.Shield, true));
            actions.Add(new ActionDefinition("restore-network", "이더넷을 DHCP로 복구", "유선 이더넷을 DHCP 모드로 되돌립니다. 테스트 종료나 롤백 때 사용합니다.", IconKind.Network, true, true));
            actions.Add(new ActionDefinition("docs", "도움말 문서 열기", "자동화, SD카드, RPi4 네트워크 부팅 문서 폴더를 엽니다.", IconKind.Doc, false));
        }

        private void BuildUi()
        {
            var root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.ColumnCount = 2;
            root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 306));
            root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            root.RowCount = 1;
            Controls.Add(root);

            sidebar = new Panel();
            sidebar.Dock = DockStyle.Fill;
            sidebar.BackColor = sidebarBg;
            sidebar.Padding = new Padding(22, 22, 18, 18);
            root.Controls.Add(sidebar, 0, 0);

            BuildSidebar();

            main = new Panel();
            main.Dock = DockStyle.Fill;
            main.BackColor = bg;
            main.Padding = new Padding(28);
            root.Controls.Add(main, 1, 0);

            BuildMain();
        }

        private void BuildSidebar()
        {
            var layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.RowCount = 4;
            layout.ColumnCount = 1;
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 92));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 136));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
            sidebar.Controls.Add(layout);

            var brand = new Panel { Dock = DockStyle.Fill };
            brand.Paint += delegate(object sender, PaintEventArgs e)
            {
                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                DrawAppMark(e.Graphics, new Rectangle(2, 5, 48, 48));
            };

            var title = new Label();
            title.Text = "RPI Netboot";
            title.ForeColor = Color.White;
            title.Font = new Font("Segoe UI Semibold", 18f, FontStyle.Bold);
            title.Location = new Point(62, 4);
            title.AutoSize = true;
            brand.Controls.Add(title);

            var sub = new Label();
            sub.Text = "Windows 서버 자동화";
            sub.ForeColor = sidebarMuted;
            sub.Font = new Font("Segoe UI", 9.5f);
            sub.Location = new Point(64, 39);
            sub.AutoSize = true;
            brand.Controls.Add(sub);
            layout.Controls.Add(brand, 0, 0);

            navList = new FlowLayoutPanel();
            navList.Dock = DockStyle.Fill;
            navList.FlowDirection = FlowDirection.TopDown;
            navList.WrapContents = false;
            navList.AutoScroll = true;
            navList.Padding = new Padding(0, 4, 0, 0);
            navList.BackColor = sidebarBg;
            layout.Controls.Add(navList, 0, 1);

            foreach (ActionDefinition action in actions)
            {
                var button = new NavButton();
                button.Width = 246;
                button.Height = 54;
                button.Margin = new Padding(0, 0, 0, 8);
                button.Text = action.Title;
                button.Icon = action.Icon;
                button.Tag = action.Task;
                button.AccessibleName = action.Title;
                button.AccessibleDescription = action.Description;
                tips.SetToolTip(button, action.Description);
                button.Click += delegate { SelectTask((string)button.Tag); };
                navList.Controls.Add(button);
            }
            navList.Resize += delegate
            {
                foreach (Control child in navList.Controls)
                {
                    child.Width = Math.Max(218, navList.ClientSize.Width - 8);
                }
            };

            var info = new SoftPanel();
            info.Dock = DockStyle.Fill;
            info.Padding = new Padding(14);
            info.FillColor = Color.FromArgb(36, 48, 44);
            info.BorderColor = Color.FromArgb(56, 70, 65);
            layout.Controls.Add(info, 0, 2);

            var infoTitle = new Label();
            infoTitle.Text = "권장 순서";
            infoTitle.ForeColor = Color.White;
            infoTitle.Font = new Font("Segoe UI Semibold", 10f, FontStyle.Bold);
            infoTitle.Dock = DockStyle.Top;
            infoTitle.Height = 22;
            info.Controls.Add(infoTitle);

            var infoText = new Label();
            infoText.Text = "1 상태 확인\n2 무료 서비스 시작\n3 boot 복사\n4 rootfs 준비\n5 RPi4 재부팅";
            infoText.ForeColor = sidebarMuted;
            infoText.Font = new Font("Segoe UI", 9.2f);
            infoText.Dock = DockStyle.Fill;
            info.Controls.Add(infoText);

            var version = new Label();
            version.Text = "자동화 UI 빌드";
            version.ForeColor = Color.FromArgb(128, 141, 134);
            version.TextAlign = ContentAlignment.BottomLeft;
            version.Dock = DockStyle.Fill;
            layout.Controls.Add(version, 0, 3);
        }

        private void BuildMain()
        {
            var layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.ColumnCount = 2;
            layout.RowCount = 4;
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 64));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 36));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 132));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 150));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 190));
            main.Controls.Add(layout);

            var header = new TableLayoutPanel();
            header.Dock = DockStyle.Fill;
            header.BackColor = bg;
            header.ColumnCount = 2;
            header.RowCount = 1;
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 176));
            layout.Controls.Add(header, 0, 0);
            layout.SetColumnSpan(header, 2);

            var headerText = new Panel { Dock = DockStyle.Fill, BackColor = bg, Padding = new Padding(0, 0, 18, 0) };
            header.Controls.Add(headerText, 0, 0);

            pageTitle = new Label();
            pageTitle.Text = "상태 확인";
            pageTitle.ForeColor = ink;
            pageTitle.Font = new Font("Segoe UI Semibold", 24f, FontStyle.Bold);
            pageTitle.Dock = DockStyle.Top;
            pageTitle.Height = 50;
            pageTitle.AutoEllipsis = true;
            headerText.Controls.Add(pageTitle);

            pageSubtitle = new Label();
            pageSubtitle.Text = "현재 서버 PC와 Raspberry Pi 네트워크 부팅 준비 상태를 확인합니다.";
            pageSubtitle.ForeColor = muted;
            pageSubtitle.Font = new Font("Segoe UI", 10.5f);
            pageSubtitle.Dock = DockStyle.Fill;
            pageSubtitle.AutoSize = false;
            pageSubtitle.AutoEllipsis = true;
            pageSubtitle.Padding = new Padding(3, 4, 0, 0);
            headerText.Controls.Add(pageSubtitle);
            pageSubtitle.BringToFront();

            statusLabel = new Label();
            statusLabel.Text = "대기 중";
            statusLabel.ForeColor = teal;
            statusLabel.BackColor = tealSoft;
            statusLabel.Font = new Font("Segoe UI Semibold", 10f, FontStyle.Bold);
            statusLabel.TextAlign = ContentAlignment.MiddleCenter;
            statusLabel.Dock = DockStyle.Top;
            statusLabel.Height = 40;
            statusLabel.Margin = new Padding(0, 8, 0, 0);
            statusLabel.AutoEllipsis = true;
            header.Controls.Add(statusLabel, 1, 0);

            var cards = new TableLayoutPanel();
            cards.Dock = DockStyle.Fill;
            cards.ColumnCount = 4;
            cards.RowCount = 1;
            cards.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
            cards.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
            cards.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
            cards.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
            layout.Controls.Add(cards, 0, 1);
            layout.SetColumnSpan(cards, 2);

            cards.Controls.Add(CreateMetricCard("서버 PC", "10.73.0.10", "유선 이더넷 고정 IP"), 0, 0);
            cards.Controls.Add(CreateMetricCard("저장소", "D:\\", "tftp / rootfs / downloads"), 1, 0);
            cards.Controls.Add(CreateMetricCard("넷부팅 대상", "RPi4만", "Zero 2 W는 SD 부팅"), 2, 0);
            cards.Controls.Add(CreateMetricCard("현재 핵심", "rootfs", "D:\\rootfs\\<serial> 채우기"), 3, 0);

            var taskPanel = new SoftPanel();
            taskPanel.Dock = DockStyle.Fill;
            taskPanel.Margin = new Padding(0, 14, 14, 14);
            taskPanel.Padding = new Padding(22);
            taskPanel.FillColor = Color.White;
            taskPanel.BorderColor = cardBorder;
            layout.Controls.Add(taskPanel, 0, 2);

            var taskLayout = new TableLayoutPanel();
            taskLayout.Dock = DockStyle.Fill;
            taskLayout.ColumnCount = 1;
            taskLayout.RowCount = 3;
            taskLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
            taskLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            taskLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 84));
            taskPanel.Controls.Add(taskLayout);

            var taskHeader = new Label();
            taskHeader.Text = "실행 작업";
            taskHeader.ForeColor = ink;
            taskHeader.Font = new Font("Segoe UI Semibold", 15f, FontStyle.Bold);
            taskHeader.Dock = DockStyle.Fill;
            taskHeader.AutoEllipsis = true;
            taskLayout.Controls.Add(taskHeader, 0, 0);

            taskTextBox = new TextBox();
            taskTextBox.Name = "TaskText";
            taskTextBox.Text = "";
            taskTextBox.ForeColor = muted;
            taskTextBox.BackColor = Color.White;
            taskTextBox.Font = new Font("Segoe UI", 10.2f);
            taskTextBox.Dock = DockStyle.Fill;
            taskTextBox.Multiline = true;
            taskTextBox.ReadOnly = true;
            taskTextBox.WordWrap = true;
            taskTextBox.BorderStyle = BorderStyle.None;
            taskTextBox.ScrollBars = ScrollBars.None;
            taskTextBox.TabStop = false;
            taskLayout.Controls.Add(taskTextBox, 0, 1);

            var actionRow = new FlowLayoutPanel();
            actionRow.Dock = DockStyle.Fill;
            actionRow.FlowDirection = FlowDirection.LeftToRight;
            actionRow.WrapContents = true;
            actionRow.Padding = new Padding(0, 12, 0, 0);
            actionRow.BackColor = Color.White;
            taskLayout.Controls.Add(actionRow, 0, 2);

            primaryButton = CreateMainButton("실행", teal, Color.White);
            primaryButton.Width = 204;
            primaryButton.Margin = new Padding(0, 0, 8, 8);
            primaryButton.AccessibleName = "선택한 작업 실행";
            tips.SetToolTip(primaryButton, "현재 선택한 자동화 작업을 실행합니다.");
            primaryButton.Click += delegate { RunSelectedTask(); };
            actionRow.Controls.Add(primaryButton);

            secondaryButton = CreateMainButton("문서 열기", Color.FromArgb(237, 241, 236), ink);
            secondaryButton.Width = 132;
            secondaryButton.Margin = new Padding(0, 0, 8, 8);
            secondaryButton.AccessibleName = "문서 폴더 열기";
            tips.SetToolTip(secondaryButton, "자동화 사용법과 테스트 체크리스트가 들어 있는 docs 폴더를 엽니다.");
            secondaryButton.Click += delegate { OpenDocsFolder(); };
            actionRow.Controls.Add(secondaryButton);

            var utility = new Button();
            utility.Text = "D:\\ 열기";
            utility.FlatStyle = FlatStyle.Flat;
            utility.Font = new Font("Segoe UI Semibold", 10f, FontStyle.Bold);
            utility.ForeColor = ink;
            utility.BackColor = Color.FromArgb(237, 241, 236);
            utility.Size = new Size(110, 52);
            utility.Margin = new Padding(0, 0, 8, 8);
            utility.FlatAppearance.BorderSize = 0;
            utility.Cursor = Cursors.Hand;
            utility.AutoEllipsis = true;
            utility.AccessibleName = "D 드라이브 저장소 열기";
            tips.SetToolTip(utility, "TFTP, rootfs, downloads 폴더가 있는 D:\\ 저장소를 엽니다.");
            utility.Click += delegate { OpenPath("D:\\"); };
            actionRow.Controls.Add(utility);

            var help = new SoftPanel();
            help.Dock = DockStyle.Fill;
            help.Margin = new Padding(0, 14, 0, 14);
            help.Padding = new Padding(20);
            help.FillColor = Color.FromArgb(250, 252, 250);
            help.BorderColor = Color.FromArgb(211, 222, 215);
            layout.Controls.Add(help, 1, 2);

            helpTitle = new Label();
            helpTitle.Text = "도움말";
            helpTitle.ForeColor = ink;
            helpTitle.Font = new Font("Segoe UI Semibold", 14f, FontStyle.Bold);
            helpTitle.Dock = DockStyle.Top;
            helpTitle.Height = 34;
            help.Controls.Add(helpTitle);

            helpBody = new TextBox();
            helpBody.Text = "";
            helpBody.ForeColor = Color.FromArgb(73, 88, 80);
            helpBody.BackColor = Color.FromArgb(250, 252, 250);
            helpBody.Font = new Font("Segoe UI", 10f);
            helpBody.Dock = DockStyle.Fill;
            helpBody.Multiline = true;
            helpBody.ReadOnly = true;
            helpBody.WordWrap = true;
            helpBody.BorderStyle = BorderStyle.None;
            helpBody.ScrollBars = ScrollBars.Vertical;
            helpBody.TabStop = false;
            help.Controls.Add(helpBody);

            var logPanel = new SoftPanel();
            logPanel.Dock = DockStyle.Fill;
            logPanel.Padding = new Padding(14);
            logPanel.FillColor = Color.FromArgb(19, 25, 23);
            logPanel.BorderColor = Color.FromArgb(35, 45, 41);
            layout.Controls.Add(logPanel, 0, 3);
            layout.SetColumnSpan(logPanel, 2);

            var logTitle = new Label();
            logTitle.Text = "실행 로그";
            logTitle.ForeColor = Color.White;
            logTitle.Font = new Font("Segoe UI Semibold", 10.5f, FontStyle.Bold);
            logTitle.Dock = DockStyle.Top;
            logTitle.Height = 26;
            logPanel.Controls.Add(logTitle);

            logBox = new TextBox();
            logBox.Multiline = true;
            logBox.ReadOnly = true;
            logBox.ScrollBars = ScrollBars.Vertical;
            logBox.BackColor = Color.FromArgb(19, 25, 23);
            logBox.ForeColor = Color.FromArgb(220, 230, 224);
            logBox.BorderStyle = BorderStyle.None;
            logBox.Font = new Font("Consolas", 9.5f);
            logBox.Dock = DockStyle.Fill;
            logPanel.Controls.Add(logBox);
            logBox.BringToFront();
        }

        private Control CreateMetricCard(string title, string value, string description)
        {
            var card = new SoftPanel();
            card.Dock = DockStyle.Fill;
            card.Margin = new Padding(0, 0, 12, 0);
            card.Padding = new Padding(16);
            card.FillColor = Color.White;
            card.BorderColor = cardBorder;

            var content = new TableLayoutPanel();
            content.Dock = DockStyle.Fill;
            content.BackColor = Color.White;
            content.ColumnCount = 1;
            content.RowCount = 3;
            content.RowStyles.Add(new RowStyle(SizeType.Absolute, 26));
            content.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
            content.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            card.Controls.Add(content);

            var titleLabel = new Label();
            titleLabel.Text = title;
            titleLabel.ForeColor = muted;
            titleLabel.Font = new Font("Segoe UI Semibold", 9.6f, FontStyle.Bold);
            titleLabel.Dock = DockStyle.Fill;
            titleLabel.AutoEllipsis = true;
            titleLabel.BackColor = Color.White;
            content.Controls.Add(titleLabel, 0, 0);

            var valueLabel = new Label();
            valueLabel.Text = value;
            valueLabel.ForeColor = ink;
            valueLabel.Font = new Font("Segoe UI Semibold", 20f, FontStyle.Bold);
            valueLabel.Dock = DockStyle.Fill;
            valueLabel.AutoEllipsis = true;
            valueLabel.BackColor = Color.White;
            content.Controls.Add(valueLabel, 0, 1);

            var descLabel = new Label();
            descLabel.Text = description;
            descLabel.ForeColor = muted;
            descLabel.Font = new Font("Segoe UI", 9f);
            descLabel.Dock = DockStyle.Fill;
            descLabel.AutoEllipsis = true;
            descLabel.BackColor = Color.White;
            content.Controls.Add(descLabel, 0, 2);
            return card;
        }

        private Button CreateMainButton(string text, Color fill, Color textColor)
        {
            var button = new Button();
            button.Text = text;
            button.FlatStyle = FlatStyle.Flat;
            button.Font = new Font("Segoe UI Semibold", 10f, FontStyle.Bold);
            button.ForeColor = textColor;
            button.BackColor = fill;
            button.Size = new Size(176, 52);
            button.FlatAppearance.BorderSize = 0;
            button.Cursor = Cursors.Hand;
            button.MinimumSize = new Size(132, 52);
            button.AutoEllipsis = true;
            button.TextAlign = ContentAlignment.MiddleCenter;
            return button;
        }

        private void SelectTask(string task)
        {
            selectedTask = task;
            ActionDefinition action = FindAction(task);
            if (action == null) return;

            pageTitle.Text = action.Title;
            pageSubtitle.Text = action.Description;
            primaryButton.Text = GetPrimaryButtonText(action);
            primaryButton.BackColor = action.Destructive ? amber : teal;
            primaryButton.AccessibleDescription = action.Description;

            foreach (Control c in navList.Controls)
            {
                var nav = c as NavButton;
                if (nav != null)
                {
                    nav.Selected = ((string)nav.Tag == task);
                    nav.Invalidate();
                }
            }

            if (taskTextBox != null)
            {
                SetMultilineText(taskTextBox, GetTaskBody(action));
            }
            helpTitle.Text = action.Title + " 도움말";
            SetMultilineText(helpBody, GetHelpText(action.Task));
        }

        private void SetMultilineText(TextBox box, string text)
        {
            if (box == null) return;
            box.Text = (text ?? "").Replace("\r\n", "\n").Replace("\n", Environment.NewLine);
            box.SelectionStart = 0;
            box.SelectionLength = 0;
            box.ScrollToCaret();
        }

        private string GetTaskBody(ActionDefinition action)
        {
            string badge = GetRiskBadge(action);
            return action.Description + Environment.NewLine +
                   "작업 성격: " + badge;
        }

        private string GetRiskBadge(ActionDefinition action)
        {
            if (action.Destructive)
            {
                return "위험: 디스크/네트워크 설정 변경, 실행 전 대상 확인 필요";
            }
            if (action.RequiresAdmin)
            {
                return "주의: 관리자 권한 필요, Windows 시스템 설정 변경";
            }
            if (action.Task == "sync-tftp")
            {
                return "주의: D:\\tftp 파일 복사와 무결성 검사";
            }
            return "안전: 읽기 전용 확인 작업";
        }

        private string GetPrimaryButtonText(ActionDefinition action)
        {
            switch (action.Task)
            {
                case "status": return "상태 확인 실행";
                case "server-setup": return "서버 PC 자동 준비";
                case "lite-provider-start": return "무료 서비스 시작";
                case "lite-provider-stop": return "무료 서비스 중지";
                case "install-services": return "haneWIN 설치 실행";
                case "configure-services": return "haneWIN 설정 적용";
                case "prepare-sd": return "SD카드에 EEPROM 쓰기";
                case "copy-boot": return "부팅파일 복사 실행";
                case "rootfs-status": return "rootfs 상태 확인";
                case "rootfs-prepare": return "rootfs 안내 만들기";
                case "zero2w-gadget-sd": return "gadget SD 패치";
                case "verify": return "전체 상태 다시 확인";
                case "sync-tftp": return "TFTP 복사/검증 실행";
                case "firewall": return "방화벽 규칙 적용";
                case "restore-network": return "이더넷 DHCP로 복구";
                case "docs": return "도움말 문서 열기";
                default: return "실행";
            }
        }

        private string GetHelpText(string task)
        {
            switch (task)
            {
                case "status":
                    return "처음에는 이 버튼을 누르세요. D: 저장소, S: SD카드, 이더넷 IP, 공유기 연결, 서비스 포트 상태를 읽기 전용으로 확인합니다.\n\n다음: 정상이면 무료 부팅 서비스 시작으로, 문제가 있으면 서버 PC 자동 준비로 갑니다.";
                case "server-setup":
                    return "서버 PC를 네트워크 부팅용으로 맞춥니다. D:\\ 바로 아래에 tftp/rootfs/downloads를 만들고 유선 이더넷을 10.73.0.10으로 적용합니다.\n\n다음: 무료 부팅 서비스 시작을 누릅니다.";
                case "lite-provider-start":
                    return "haneWIN 없이 테스트하기 위한 무료 provider입니다. 프로그램이 자체 DHCP/TFTP 서버를 빌드하고, WinNFSd를 내려받아 D:\\rootfs를 /rpi로 공유합니다.\n\n실행하면 기존 haneWIN 서비스는 포트 충돌을 피하려고 중지됩니다. 다음: 전체 상태 다시 확인을 누르고 Pi 전원을 다시 넣습니다.";
                case "lite-provider-stop":
                    return "무료 provider가 차지한 DHCP/TFTP/NFS 포트를 정리합니다. 테스트를 멈추거나 다른 provider를 쓰기 전에 누릅니다.\n\n다음: 필요하면 haneWIN 설정 또는 무료 부팅 서비스 시작을 다시 선택합니다.";
                case "install-services":
                    return "haneWIN DHCP/TFTP/NFS를 설치합니다. 이 도구는 실제 제품이고 내가 만든 이름은 아니지만, 미등록 상태에서는 30일 평가판입니다.\n\n기본 테스트는 무료 부팅 서비스 시작을 먼저 쓰세요. haneWIN은 빠른 비교/검증용 보조 provider로만 봅니다.";
                case "configure-services":
                    return "haneWIN을 실제 랩 설정에 맞춥니다. DHCP는 이더넷 10.73.0.10에만 응답하게 하고, Pi 예약 IP 60대, TFTP root D:\\tftp, NFS export D:\\rootfs -> /rpi를 적용합니다.\n\n무료 provider가 안 될 때의 비교용 경로입니다.";
                case "prepare-sd":
                    return "RPi4 전용입니다. S: SD카드만 지웁니다. D: rpi 저장소는 선택하면 안 됩니다.\n\n다음: RPi4를 이 SD카드로 한 번 부팅합니다. Zero 2 W용 SD는 별도 버튼을 쓰세요.";
                case "copy-boot":
                    return "RPi4용 boot 파티션이 필요합니다. EEPROM SD가 아닙니다. start4.elf/fixup4.dat가 있는 FAT32 파티션을 TFTP 폴더로 복사합니다.\n\n다음: rootfs 상태 확인을 누릅니다.";
                case "rootfs-status":
                    return "테스트 RPi4의 rootfs 폴더를 확인합니다. D:\\rootfs\\<serial> 안에 init, bin, etc, usr가 있어야 커널 이후 부팅됩니다.\n\n비어 있으면 rootfs 준비 안내 만들기를 누르세요.";
                case "rootfs-prepare":
                    return "Windows 탐색기 복사 대신 Pi/Linux helper용 rsync 스크립트를 만듭니다. Linux 권한, 소유자, 심볼릭 링크를 보존하기 위한 흐름입니다.\n\n생성 위치: D:\\downloads";
                case "zero2w-gadget-sd":
                    return "Zero 2 W는 네트워크 부팅 대상이 아닙니다. S:의 Raspberry Pi OS boot 파티션을 USB Ethernet gadget용으로 패치합니다.\n\n연결: PWR IN이 아니라 mini HDMI 옆 USB data 포트를 PC에 꽂습니다.";
                case "verify":
                    return "무료 부팅 서비스 시작 후에 누릅니다. UDP 67/69, NFS 2049, TFTP 파일, rootfs 흐름을 다시 봅니다.\n\n네트워크 부팅 테스트 대상은 RPi4만입니다.";
                case "sync-tftp":
                    return "생성된 cmdline/config를 D:\\tftp에 다시 반영합니다. 파일이 NUL로 깨지는 문제를 잡기 위해 검증도 같이 합니다.\n\n다음: 전체 상태 다시 확인으로 파일과 포트를 확인합니다.";
                case "firewall":
                    return "Windows 방화벽에서 DHCP, TFTP, NFS, iSCSI 포트를 열어줍니다. 네트워크 부팅 서비스를 실행하기 전에 적용합니다.\n\n다음: 서비스 설치 또는 전체 상태 다시 확인을 진행합니다.";
                case "restore-network":
                    return "테스트망을 정리하거나 원래 인터넷 환경으로 되돌릴 때 유선 이더넷을 DHCP로 복구합니다.\n\n다음: 필요하면 공유기/PC 네트워크를 원래 구성으로 되돌립니다.";
                case "docs":
                    return "현재 자동화 흐름과 첫 Pi 테스트 절차가 적힌 문서 폴더를 엽니다.";
                default:
                    return "";
            }
        }

        private Control FindControlByName(Control root, string name)
        {
            foreach (Control child in root.Controls)
            {
                if (child.Name == name) return child;
                Control nested = FindControlByName(child, name);
                if (nested != null) return nested;
            }
            return null;
        }

        private ActionDefinition FindAction(string task)
        {
            foreach (ActionDefinition action in actions)
            {
                if (action.Task == task) return action;
            }
            return null;
        }

        private void RunSelectedTask()
        {
            ActionDefinition action = FindAction(selectedTask);
            if (action == null || isRunning) return;

            if (!File.Exists(scriptPath))
            {
                MessageBox.Show("자동화 스크립트를 찾을 수 없습니다.\n\n찾은 위치:\n" + scriptPath + "\n\n해결:\n프로그램을 프로젝트 폴더에서 다시 실행하거나 README의 빌드/실행 위치를 확인하세요.", "RPI 네트워크 부팅 관리자", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (action.Task == "docs")
            {
                OpenDocsFolder();
                return;
            }

            if (action.RequiresAdmin && !IsCurrentProcessAdmin())
            {
                LaunchAdmin(action.Task);
                return;
            }

            if (RequiresConfirmation(action))
            {
                DialogResult result = MessageBox.Show(
                    GetConfirmationText(action),
                    "확인 필요",
                    MessageBoxButtons.YesNo,
                    action.Destructive ? MessageBoxIcon.Warning : MessageBoxIcon.Information,
                    MessageBoxDefaultButton.Button2);
                if (result != DialogResult.Yes) return;
            }

            string args = BuildPowerShellArguments(action);
            RunPowerShell(action.Title, args);
        }

        private string BuildPowerShellArguments(ActionDefinition action)
        {
            string command = BuildPowerShellCommand(action);
            string encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(command));
            return "-NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand " + encoded;
        }

        private string BuildPowerShellCommand(ActionDefinition action)
        {
            string commandPrefix = "$enc=New-Object System.Text.UTF8Encoding -ArgumentList $false; " +
                                   "[Console]::OutputEncoding=$enc; $OutputEncoding=$enc; " +
                                   "$ProgressPreference='SilentlyContinue'; ";
            string toolPath;
            switch (action.Task)
            {
                case "rootfs-status":
                    toolPath = Path.Combine(projectRoot, "tools", "rootfs-helper.ps1");
                    return commandPrefix + "& " + PsSingle(toolPath) + " status 3>&1 4>&1 5>&1 6>&1";
                case "rootfs-prepare":
                    toolPath = Path.Combine(projectRoot, "tools", "rootfs-helper.ps1");
                    return commandPrefix + "& " + PsSingle(toolPath) + " make-script 3>&1 4>&1 5>&1 6>&1";
                case "zero2w-gadget-sd":
                    toolPath = Path.Combine(projectRoot, "tools", "zero2w-gadget-sd.ps1");
                    return commandPrefix + "& " + PsSingle(toolPath) + " apply -DriveLetter S -Yes 3>&1 4>&1 5>&1 6>&1";
            }

            string command = "$enc=New-Object System.Text.UTF8Encoding -ArgumentList $false; " +
                             "[Console]::OutputEncoding=$enc; $OutputEncoding=$enc; " +
                             "$ProgressPreference='SilentlyContinue'; " +
                             "& " + PsSingle(scriptPath) + " -Task " + PsSingle(action.Task);
            if (action.Destructive)
            {
                command += " -Yes";
            }
            command += " 3>&1 4>&1 5>&1 6>&1";
            return command;
        }

        private bool RequiresConfirmation(ActionDefinition action)
        {
            return action.RequiresAdmin || action.Destructive;
        }

        private string GetConfirmationText(ActionDefinition action)
        {
            switch (action.Task)
            {
                case "server-setup":
                    return "서버 PC 자동 준비를 실행합니다.\n\n변경 대상:\n- 유선 이더넷 IP: 10.73.0.10\n- 저장소 구조: D:\\tftp, D:\\rootfs, D:\\downloads\n- TFTP 파일 동기화와 방화벽 규칙\n\nD:가 rpi 저장소이고 이 PC가 서버 PC이면 [예]를 누르세요.";
                case "lite-provider-start":
                    return "무료 부팅 서비스 provider를 시작합니다.\n\n실행 내용:\n- 내장 DHCP/TFTP 서버 빌드 및 시작\n- WinNFSd 다운로드 및 NFS 시작\n- haneWIN DHCP/TFTP/NFS 서비스 중지\n- DHCP/TFTP/NFS 방화벽 규칙 확인\n\nPi가 다음 DHCP에서 10.73.0.155 같은 예약 IP를 받게 됩니다. 계속하려면 [예]를 누르세요.";
                case "lite-provider-stop":
                    return "무료 부팅 서비스 provider를 중지합니다.\n\n중지 대상:\n- 내장 DHCP/TFTP 서버\n- WinNFSd NFS 서버\n\n테스트를 멈추거나 다른 provider로 전환할 때만 [예]를 누르세요.";
                case "install-services":
                    return "haneWIN 평가판 설치를 실행합니다.\n\nPi 부팅에 필요한 역할:\n- DHCP: Pi에게 부팅 서버 주소 안내\n- TFTP: 커널/부팅 파일 전달\n- NFS: rootfs 폴더 제공\n\n현재 설치되는 haneWIN DHCP/TFTP/NFS는 빠른 검증용 30일 평가판 provider입니다. 기본 테스트는 무료 부팅 서비스 시작 버튼을 우선 사용합니다.\n\nhaneWIN 비교 테스트가 필요하면 [예]를 누르세요.";
                case "configure-services":
                    return "부팅 서비스 설정을 실제 랩 값으로 적용합니다.\n\n변경 대상:\n- DHCP: 이더넷 10.73.0.10 전용, Wi-Fi DHCP 제거\n- 예약 IP: 등록된 Pi 60대 적용\n- TFTP root: D:\\tftp\n- NFS export: D:\\rootfs -> /rpi\n- 서비스 재시작\n\n이 PC가 Raspberry Pi 부팅 서버이면 [예]를 누르세요.";
                case "prepare-sd":
                    return "RPi4 EEPROM SD를 만듭니다.\n\n대상: S:\n실행 내용: Pi 4 Network Boot EEPROM 이미지 쓰기\n주의: S:의 모든 내용 삭제\n\n네트워크 부팅 대상은 RPi4만입니다. 계속하려면 [예]를 누르세요.";
                case "zero2w-gadget-sd":
                    return "Zero 2 W USB gadget SD를 패치합니다.\n\n대상: S:\n변경 파일: config.txt, cmdline.txt, user-data, ssh marker\n주의: Zero 2 W는 SD로 부팅합니다. RPi4 네트워크 부팅 대상에 넣지 않습니다.\n\nS:가 Zero 2 W용 OS SD이면 [예]를 누르세요.";
                case "firewall":
                    return "부팅 포트 방화벽 규칙을 추가합니다.\n\n열 포트:\n- DHCP UDP 67\n- TFTP UDP 69\n- NFS TCP 2049\n- iSCSI TCP 3260\n\n이 PC가 격리된 10.73.0.0/24 부팅 서버이면 [예]를 누르세요.";
                case "restore-network":
                    return "유선 이더넷을 DHCP로 복구합니다.\n\n변경 대상: 이더넷 어댑터\n결과: 10.73.0.10 고정 IP가 제거되고 DHCP 주소를 다시 받습니다.\n\n테스트망을 종료할 때만 [예]를 누르세요.";
                default:
                    return action.Title + " 작업을 실행합니다.\n\n" + action.Description + "\n\n계속할까요?";
            }
        }

        private void RunPowerShell(string title, string arguments)
        {
            isRunning = true;
            SetBusy(true, title + " 실행 중");
            AppendLog("");
            AppendLog("[시작] " + title);

            var psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = arguments;
            psi.WorkingDirectory = projectRoot;
            psi.UseShellExecute = false;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.CreateNoWindow = true;
            psi.StandardOutputEncoding = Encoding.UTF8;
            psi.StandardErrorEncoding = Encoding.UTF8;

            var process = new Process();
            process.StartInfo = psi;
            process.EnableRaisingEvents = true;
            runningProcess = process;
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e)
            {
                if (e.Data != null) AppendLog(e.Data);
            };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e)
            {
                if (e.Data != null && !IsPowerShellXmlNoise(e.Data)) AppendLog("오류: " + e.Data);
            };
            process.Exited += delegate
            {
                int code = process.ExitCode;
                if (IsDisposed || !IsHandleCreated) return;
                BeginInvoke(new Action(delegate
                {
                    AppendLog("[완료] exit code " + code);
                    SetBusy(false, code == 0 ? "완료" : "오류");
                    runningProcess = null;
                    process.Dispose();
                }));
            };

            try
            {
                process.Start();
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
            }
            catch (Exception ex)
            {
                SetBusy(false, "실행 실패");
                AppendLog("ERR " + ex.Message);
                runningProcess = null;
                process.Dispose();
            }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (isRunning)
            {
                DialogResult result = MessageBox.Show("작업이 아직 실행 중입니다.\n\n종료하면 실행 중인 PowerShell 작업도 중단합니다. 종료할까요?", "실행 중", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
                if (result != DialogResult.Yes)
                {
                    e.Cancel = true;
                    return;
                }

                try
                {
                    if (runningProcess != null && !runningProcess.HasExited)
                    {
                        runningProcess.Kill();
                    }
                }
                catch
                {
                }
            }
            base.OnFormClosing(e);
        }

        private void SetBusy(bool busy, string status)
        {
            isRunning = busy;
            primaryButton.Enabled = !busy;
            secondaryButton.Enabled = !busy;
            foreach (Control c in navList.Controls) c.Enabled = !busy;
            statusLabel.Text = status;
            statusLabel.BackColor = busy ? Color.FromArgb(255, 246, 220) : tealSoft;
            statusLabel.ForeColor = busy ? amber : teal;
        }

        private bool IsPowerShellXmlNoise(string line)
        {
            if (string.IsNullOrWhiteSpace(line)) return true;
            string trimmed = line.TrimStart();
            return trimmed.StartsWith("#< CLIXML", StringComparison.OrdinalIgnoreCase) ||
                   trimmed.StartsWith("<Objs ", StringComparison.OrdinalIgnoreCase) ||
                   trimmed.StartsWith("</Objs>", StringComparison.OrdinalIgnoreCase) ||
                   trimmed.Contains("System.Management.Automation.ProgressRecord");
        }

        private void AppendLog(string line)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action<string>(AppendLog), line);
                return;
            }
            logBox.AppendText(line + Environment.NewLine);
        }

        private void OpenDocsFolder()
        {
            string guide = Path.Combine(projectRoot, "docs", "index.html");
            if (File.Exists(guide))
            {
                OpenPath(guide);
                return;
            }
            OpenPath(Path.Combine(projectRoot, "docs"));
        }

        private void OpenPath(string path)
        {
            try
            {
                if (Directory.Exists(path) || File.Exists(path))
                {
                    Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true });
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "열기 실패", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private bool IsCurrentProcessAdmin()
        {
            WindowsIdentity identity = WindowsIdentity.GetCurrent();
            WindowsPrincipal principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }

        private void LaunchAdmin(string task)
        {
            string adminExe = Path.Combine(projectRoot, "RPI-Netboot-Manager-Admin.exe");
            string updatedAdminExe = Path.Combine(projectRoot, "RPI-Netboot-Manager-Admin-Update.exe");
            if (File.Exists(updatedAdminExe) && (!File.Exists(adminExe) || File.GetLastWriteTimeUtc(updatedAdminExe) >= File.GetLastWriteTimeUtc(adminExe)))
            {
                adminExe = updatedAdminExe;
            }
            if (!File.Exists(adminExe))
            {
                MessageBox.Show("관리자 실행 파일을 찾을 수 없습니다.\n" + adminExe, "관리자 권한 필요", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            DialogResult result = MessageBox.Show(
                "이 작업은 관리자 권한이 필요합니다.\n\n관리자 모드로 다시 열까요?",
                "관리자 권한 필요",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Information,
                MessageBoxDefaultButton.Button1);
            if (result != DialogResult.Yes) return;

            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = adminExe,
                    Arguments = "--task " + Quote(task) + " --run",
                    WorkingDirectory = projectRoot,
                    UseShellExecute = true,
                    Verb = "runas"
                });
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "관리자 모드 실행 실패", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        private string PsSingle(string value)
        {
            return "'" + value.Replace("'", "''") + "'";
        }

        private void DrawAppMark(Graphics g, Rectangle rect)
        {
            using (GraphicsPath path = RoundedRect(rect, 12))
            using (Brush fill = new SolidBrush(teal))
            {
                g.FillPath(fill, path);
            }
            using (Pen p = new Pen(Color.White, 3))
            {
                g.DrawRectangle(p, rect.Left + 13, rect.Top + 15, 22, 17);
                g.DrawLine(p, rect.Left + 24, rect.Top + 32, rect.Left + 24, rect.Top + 39);
                g.DrawLine(p, rect.Left + 17, rect.Top + 39, rect.Left + 31, rect.Top + 39);
            }
            using (Brush b = new SolidBrush(Color.FromArgb(255, 217, 122)))
            {
                g.FillEllipse(b, rect.Left + 9, rect.Top + 8, 8, 8);
                g.FillEllipse(b, rect.Left + 32, rect.Top + 8, 8, 8);
                g.FillEllipse(b, rect.Left + 21, rect.Top + 4, 8, 8);
            }
        }

        private GraphicsPath RoundedRect(Rectangle bounds, int radius)
        {
            int d = radius * 2;
            var path = new GraphicsPath();
            path.AddArc(bounds.Left, bounds.Top, d, d, 180, 90);
            path.AddArc(bounds.Right - d, bounds.Top, d, d, 270, 90);
            path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
            path.AddArc(bounds.Left, bounds.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    internal sealed class ActionDefinition
    {
        public string Task;
        public string Title;
        public string Description;
        public IconKind Icon;
        public bool RequiresAdmin;
        public bool Destructive;

        public ActionDefinition(string task, string title, string description, IconKind icon, bool requiresAdmin, bool destructive)
        {
            Task = task;
            Title = title;
            Description = description;
            Icon = icon;
            RequiresAdmin = requiresAdmin;
            Destructive = destructive;
        }

        public ActionDefinition(string task, string title, string description, IconKind icon, bool requiresAdmin)
            : this(task, title, description, icon, requiresAdmin, false)
        {
        }
    }

    internal enum IconKind
    {
        Pulse,
        Server,
        Package,
        SdCard,
        Check,
        Sync,
        Shield,
        Network,
        Doc
    }

    internal sealed class NavButton : Control
    {
        public IconKind Icon { get; set; }
        public bool Selected { get; set; }

        public NavButton()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
            Cursor = Cursors.Hand;
            Font = new Font("Segoe UI Semibold", 10f, FontStyle.Bold);
            TabStop = true;
            AccessibleRole = AccessibleRole.PushButton;
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space)
            {
                e.Handled = true;
                OnClick(EventArgs.Empty);
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Color fill = Selected ? Color.FromArgb(38, 70, 64) : Color.FromArgb(24, 34, 31);
            Color text = Selected ? Color.White : Color.FromArgb(195, 205, 199);
            Color icon = Selected ? Color.FromArgb(132, 225, 209) : Color.FromArgb(139, 153, 146);

            using (GraphicsPath path = RoundedRect(new Rectangle(0, 0, Width - 1, Height - 1), 8))
            using (Brush b = new SolidBrush(fill))
            {
                e.Graphics.FillPath(b, path);
            }
            if (Focused)
            {
                using (Pen focus = new Pen(Color.FromArgb(255, 217, 122), 2))
                {
                    e.Graphics.DrawRectangle(focus, 2, 2, Width - 5, Height - 5);
                }
            }

            DrawIcon(e.Graphics, Icon, new Rectangle(16, 15, 24, 24), icon);
            TextRenderer.DrawText(
                e.Graphics,
                Text,
                Font,
                new Rectangle(52, 0, Width - 58, Height),
                text,
                TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }

        private void DrawIcon(Graphics g, IconKind kind, Rectangle r, Color color)
        {
            using (Pen p = new Pen(color, 2.2f))
            using (Brush b = new SolidBrush(color))
            {
                switch (kind)
                {
                    case IconKind.Pulse:
                        g.DrawLine(p, r.Left, r.Top + 13, r.Left + 5, r.Top + 13);
                        g.DrawLine(p, r.Left + 5, r.Top + 13, r.Left + 9, r.Top + 6);
                        g.DrawLine(p, r.Left + 9, r.Top + 6, r.Left + 14, r.Top + 19);
                        g.DrawLine(p, r.Left + 14, r.Top + 19, r.Left + 18, r.Top + 12);
                        g.DrawLine(p, r.Left + 18, r.Top + 12, r.Right, r.Top + 12);
                        break;
                    case IconKind.Server:
                        g.DrawRectangle(p, r.Left + 2, r.Top + 4, r.Width - 4, 7);
                        g.DrawRectangle(p, r.Left + 2, r.Top + 14, r.Width - 4, 7);
                        g.FillEllipse(b, r.Right - 8, r.Top + 6, 3, 3);
                        g.FillEllipse(b, r.Right - 8, r.Top + 16, 3, 3);
                        break;
                    case IconKind.Package:
                        g.DrawRectangle(p, r.Left + 4, r.Top + 5, r.Width - 8, r.Height - 9);
                        g.DrawLine(p, r.Left + 4, r.Top + 11, r.Right - 4, r.Top + 11);
                        g.DrawLine(p, r.Left + 12, r.Top + 5, r.Left + 12, r.Top + 11);
                        break;
                    case IconKind.SdCard:
                        g.DrawRectangle(p, r.Left + 5, r.Top + 3, r.Width - 10, r.Height - 5);
                        g.DrawLine(p, r.Right - 8, r.Top + 3, r.Right - 3, r.Top + 8);
                        for (int i = 0; i < 4; i++) g.DrawLine(p, r.Left + 8 + i * 4, r.Bottom - 7, r.Left + 8 + i * 4, r.Bottom - 3);
                        break;
                    case IconKind.Check:
                        g.DrawEllipse(p, r.Left + 2, r.Top + 2, r.Width - 4, r.Height - 4);
                        g.DrawLine(p, r.Left + 7, r.Top + 13, r.Left + 11, r.Top + 17);
                        g.DrawLine(p, r.Left + 11, r.Top + 17, r.Right - 6, r.Top + 8);
                        break;
                    case IconKind.Sync:
                        g.DrawArc(p, r.Left + 3, r.Top + 4, r.Width - 8, r.Height - 8, 30, 230);
                        g.DrawArc(p, r.Left + 5, r.Top + 4, r.Width - 8, r.Height - 8, 210, 230);
                        g.FillPolygon(b, new Point[] { new Point(r.Right - 4, r.Top + 8), new Point(r.Right - 10, r.Top + 8), new Point(r.Right - 6, r.Top + 14) });
                        g.FillPolygon(b, new Point[] { new Point(r.Left + 4, r.Bottom - 8), new Point(r.Left + 10, r.Bottom - 8), new Point(r.Left + 6, r.Bottom - 14) });
                        break;
                    case IconKind.Shield:
                        g.DrawPolygon(p, new Point[] { new Point(r.Left + 12, r.Top + 3), new Point(r.Right - 4, r.Top + 8), new Point(r.Right - 7, r.Bottom - 5), new Point(r.Left + 12, r.Bottom - 2), new Point(r.Left + 4, r.Bottom - 5), new Point(r.Left + 1, r.Top + 8) });
                        break;
                    case IconKind.Network:
                        g.DrawEllipse(p, r.Left + 2, r.Top + 3, 7, 7);
                        g.DrawEllipse(p, r.Right - 9, r.Top + 3, 7, 7);
                        g.DrawEllipse(p, r.Left + 9, r.Bottom - 10, 7, 7);
                        g.DrawLine(p, r.Left + 9, r.Top + 7, r.Right - 9, r.Top + 7);
                        g.DrawLine(p, r.Left + 7, r.Top + 10, r.Left + 12, r.Bottom - 10);
                        g.DrawLine(p, r.Right - 7, r.Top + 10, r.Left + 15, r.Bottom - 10);
                        break;
                    case IconKind.Doc:
                        g.DrawRectangle(p, r.Left + 5, r.Top + 3, r.Width - 10, r.Height - 5);
                        g.DrawLine(p, r.Left + 9, r.Top + 10, r.Right - 8, r.Top + 10);
                        g.DrawLine(p, r.Left + 9, r.Top + 15, r.Right - 8, r.Top + 15);
                        break;
                }
            }
        }

        private GraphicsPath RoundedRect(Rectangle bounds, int radius)
        {
            int d = radius * 2;
            var path = new GraphicsPath();
            path.AddArc(bounds.Left, bounds.Top, d, d, 180, 90);
            path.AddArc(bounds.Right - d, bounds.Top, d, d, 270, 90);
            path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
            path.AddArc(bounds.Left, bounds.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    internal sealed class SoftPanel : Panel
    {
        public Color FillColor { get; set; }
        public Color BorderColor { get; set; }

        public SoftPanel()
        {
            FillColor = Color.White;
            BorderColor = Color.FromArgb(220, 225, 220);
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath path = RoundedRect(new Rectangle(0, 0, Width - 1, Height - 1), 8))
            using (Brush fill = new SolidBrush(FillColor))
            using (Pen border = new Pen(BorderColor))
            {
                e.Graphics.FillPath(fill, path);
                e.Graphics.DrawPath(border, path);
            }
            base.OnPaint(e);
        }

        private GraphicsPath RoundedRect(Rectangle bounds, int radius)
        {
            int d = radius * 2;
            var path = new GraphicsPath();
            path.AddArc(bounds.Left, bounds.Top, d, d, 180, 90);
            path.AddArc(bounds.Right - d, bounds.Top, d, d, 270, 90);
            path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
            path.AddArc(bounds.Left, bounds.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
    }
}
