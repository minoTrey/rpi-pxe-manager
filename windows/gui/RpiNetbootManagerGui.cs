using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
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

    internal static class UiFonts
    {
        public static readonly string Family = Resolve();

        private static string Resolve()
        {
            string[] preferred = new string[]
            {
                "Pretendard",
                "Noto Sans KR",
                "Noto Sans CJK KR",
                "맑은 고딕",
                "Malgun Gothic",
                "Segoe UI Variable Text",
                "Segoe UI"
            };

            try
            {
                using (var installed = new InstalledFontCollection())
                {
                    foreach (string name in preferred)
                    {
                        foreach (FontFamily family in installed.Families)
                        {
                            if (string.Equals(family.Name, name, StringComparison.OrdinalIgnoreCase))
                            {
                                return family.Name;
                            }
                        }
                    }
                }
            }
            catch
            {
            }

            return "Malgun Gothic";
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
        private Label storageMetricValue;
        private Button primaryButton;
        private Button secondaryButton;
        private Button storageOpenButton;
        private ToolTip tips;
        private Process runningProcess;
        private bool isRunning;
        private string selectedTask = "status";
        private CloneRpi4Request pendingCloneRequest;
        private SdImageWriteRequest pendingSdImageWriteRequest;
        private readonly bool autoRunInitialTask;

        private static readonly string UiFont = UiFonts.Family;
        private readonly Color bg = Color.FromArgb(246, 248, 250);
        private readonly Color ink = Color.FromArgb(24, 31, 38);
        private readonly Color muted = Color.FromArgb(88, 99, 111);
        private readonly Color sidebarBg = Color.FromArgb(255, 255, 255);
        private readonly Color sidebarMuted = Color.FromArgb(105, 116, 128);
        private readonly Color teal = Color.FromArgb(0, 103, 92);
        private readonly Color tealSoft = Color.FromArgb(222, 242, 238);
        private readonly Color amber = Color.FromArgb(168, 88, 20);
        private readonly Color cardBorder = Color.FromArgb(221, 227, 234);
        private readonly Color buttonSoft = Color.FromArgb(239, 243, 247);

        public MainForm(string initialTask, bool autoRun)
        {
            projectRoot = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            scriptPath = Path.Combine(projectRoot, "tools", "rpi-netboot-manager.ps1");
            autoRunInitialTask = autoRun;

            Text = "RPI 네트워크 부팅 관리자";
            AutoScaleMode = AutoScaleMode.Dpi;
            AutoScaleDimensions = new SizeF(96f, 96f);
            MinimumSize = new Size(1160, 760);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = bg;
            Font = new Font(UiFont, 9.2f, FontStyle.Regular);
            Icon = LoadAppIcon();
            tips = new ToolTip();
            tips.AutoPopDelay = 12000;
            tips.InitialDelay = 350;
            tips.ReshowDelay = 100;

            BuildActions();
            BuildUi();
            SelectTask(FindAction(initialTask) == null ? "status" : initialTask);
            Shown += delegate { FocusSelectedNav(); };
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
            actions.Add(new ActionDefinition("server-setup", "서버 PC 준비", "선택한 저장소와 이더넷 10.73.0.10 구성을 자동으로 맞춥니다.", IconKind.Server, true));
            actions.Add(new ActionDefinition("lite-provider-start", "부팅 서비스 시작", "DHCP, TFTP, NFS 서비스를 시작해 RPi4 네트워크 부팅을 받을 준비를 합니다.", IconKind.Network, true));
            actions.Add(new ActionDefinition("clone-rpi4", "새 RPi4 등록/복제", "OS SD 첫 부팅 리포트로 감지한 시리얼/MAC을 확인해 새 RPi4의 bootfs/rootfs와 내부 설정을 만듭니다.", IconKind.Package, false));
            actions.Add(new ActionDefinition("prepare-sd", "RPi4 OS SD 작성", "선택한 SD 디스크에 Raspberry Pi OS Lite 64-bit Trixie 이미지와 자동 등록 리포터를 씁니다.", IconKind.SdCard, true, true));
            actions.Add(new ActionDefinition("zero2w-gadget-sd", "Zero 2 W Gadget SD", "S: SD를 Zero 2 W USB Ethernet gadget 부팅용으로 패치합니다.", IconKind.SdCard, false, true));
            actions.Add(new ActionDefinition("docs", "도움말", "운영 절차와 복제 Runbook을 엽니다.", IconKind.Doc, false));
        }

        private void BuildUi()
        {
            var root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.ColumnCount = 2;
            root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 276));
            root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            root.RowCount = 1;
            Controls.Add(root);

            sidebar = new Panel();
            sidebar.Dock = DockStyle.Fill;
            sidebar.BackColor = sidebarBg;
            sidebar.Padding = new Padding(18, 22, 14, 18);
            root.Controls.Add(sidebar, 0, 0);

            BuildSidebar();

            main = new Panel();
            main.Dock = DockStyle.Fill;
            main.BackColor = bg;
            main.Padding = new Padding(22);
            root.Controls.Add(main, 1, 0);

            BuildMain();
        }

        private void BuildSidebar()
        {
            var layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.RowCount = 2;
            layout.ColumnCount = 1;
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 74));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            sidebar.Controls.Add(layout);

            var brand = new Panel { Dock = DockStyle.Fill };
            brand.Paint += delegate(object sender, PaintEventArgs e)
            {
                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                DrawAppMark(e.Graphics, new Rectangle(0, 4, 42, 42));
            };

            var title = new Label();
            title.Text = "RPI Netboot";
            title.ForeColor = ink;
            title.Font = new Font(UiFont, 15.0f, FontStyle.Bold);
            title.Location = new Point(54, 2);
            title.AutoSize = true;
            brand.Controls.Add(title);

            var sub = new Label();
            sub.Text = "네트워크 부팅 관리자";
            sub.ForeColor = sidebarMuted;
            sub.Font = new Font(UiFont, 8.8f, FontStyle.Regular);
            sub.Location = new Point(56, 33);
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
                button.Width = 236;
                button.Height = 46;
                button.Margin = new Padding(0, 0, 0, 5);
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
                    child.Width = Math.Max(210, navList.ClientSize.Width - 6);
                }
            };
        }

        private void BuildMain()
        {
            var layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.ColumnCount = 2;
            layout.RowCount = 4;
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 65));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 35));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 86));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 104));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 168));
            main.Controls.Add(layout);

            var header = new TableLayoutPanel();
            header.Dock = DockStyle.Fill;
            header.BackColor = bg;
            header.ColumnCount = 2;
            header.RowCount = 1;
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 146));
            layout.Controls.Add(header, 0, 0);
            layout.SetColumnSpan(header, 2);

            var headerText = new Panel { Dock = DockStyle.Fill, BackColor = bg, Padding = new Padding(0, 0, 18, 0) };
            header.Controls.Add(headerText, 0, 0);

            pageTitle = new Label();
            pageTitle.Text = "상태 확인";
            pageTitle.ForeColor = ink;
            pageTitle.Font = new Font(UiFont, 18.0f, FontStyle.Bold);
            pageTitle.Dock = DockStyle.Top;
            pageTitle.Height = 38;
            pageTitle.AutoEllipsis = true;
            headerText.Controls.Add(pageTitle);

            pageSubtitle = new Label();
            pageSubtitle.Text = "현재 서버 PC와 Raspberry Pi 네트워크 부팅 준비 상태를 확인합니다.";
            pageSubtitle.ForeColor = muted;
            pageSubtitle.Font = new Font(UiFont, 9.1f);
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
            statusLabel.Font = new Font(UiFont, 8.7f, FontStyle.Bold);
            statusLabel.TextAlign = ContentAlignment.MiddleCenter;
            statusLabel.Dock = DockStyle.Top;
            statusLabel.Height = 32;
            statusLabel.Margin = new Padding(0, 4, 0, 0);
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
            cards.Controls.Add(CreateMetricCard("저장소", GetStorageDisplayRoot(), "tftp / rootfs / tools"), 1, 0);
            cards.Controls.Add(CreateMetricCard("새 기기", "rpi-001", "기기 번호 기반 복제"), 2, 0);
            cards.Controls.Add(CreateMetricCard("넷부팅 대상", "RPi4", "Zero 2 W는 Gadget SD"), 3, 0);

            var taskPanel = new SoftPanel();
            taskPanel.Dock = DockStyle.Fill;
            taskPanel.Margin = new Padding(0, 10, 10, 10);
            taskPanel.Padding = new Padding(16);
            taskPanel.FillColor = Color.White;
            taskPanel.BorderColor = cardBorder;
            layout.Controls.Add(taskPanel, 0, 2);

            var taskLayout = new TableLayoutPanel();
            taskLayout.Dock = DockStyle.Fill;
            taskLayout.ColumnCount = 1;
            taskLayout.RowCount = 3;
            taskLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
            taskLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            taskLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 72));
            taskPanel.Controls.Add(taskLayout);

            var taskHeader = new Label();
            taskHeader.Text = "선택한 작업";
            taskHeader.ForeColor = ink;
            taskHeader.Font = new Font(UiFont, 11.5f, FontStyle.Bold);
            taskHeader.Dock = DockStyle.Fill;
            taskHeader.AutoEllipsis = true;
            taskLayout.Controls.Add(taskHeader, 0, 0);

            taskTextBox = new TextBox();
            taskTextBox.Name = "TaskText";
            taskTextBox.Text = "";
            taskTextBox.ForeColor = muted;
            taskTextBox.BackColor = Color.White;
            taskTextBox.Font = new Font(UiFont, 9.1f);
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
            actionRow.WrapContents = false;
            actionRow.Padding = new Padding(0, 8, 0, 0);
            actionRow.BackColor = Color.White;
            taskLayout.Controls.Add(actionRow, 0, 2);

            primaryButton = CreateMainButton("실행", teal, Color.White);
            primaryButton.Width = 216;
            primaryButton.Margin = new Padding(0, 0, 8, 8);
            primaryButton.AccessibleName = "선택한 작업 실행";
            tips.SetToolTip(primaryButton, "현재 선택한 자동화 작업을 실행합니다.");
            primaryButton.Click += delegate { RunSelectedTask(); };
            actionRow.Controls.Add(primaryButton);

            secondaryButton = CreateMainButton("저장소 설정", buttonSoft, ink);
            secondaryButton.Width = 130;
            secondaryButton.Margin = new Padding(0, 0, 8, 8);
            secondaryButton.FlatAppearance.BorderColor = cardBorder;
            secondaryButton.AccessibleName = "저장소 경로 설정";
            tips.SetToolTip(secondaryButton, "TFTP, rootfs, downloads, tools 폴더를 둘 저장소를 선택합니다.");
            secondaryButton.Click += delegate { ChooseStorageRoot(); };
            actionRow.Controls.Add(secondaryButton);

            storageOpenButton = CreateMainButton("저장소 열기", buttonSoft, ink);
            storageOpenButton.Width = 118;
            storageOpenButton.Margin = new Padding(0, 0, 8, 8);
            storageOpenButton.FlatAppearance.BorderColor = cardBorder;
            storageOpenButton.AccessibleName = "현재 저장소 열기";
            tips.SetToolTip(storageOpenButton, "현재 설정된 TFTP, rootfs, downloads 저장소를 엽니다.");
            storageOpenButton.Click += delegate { OpenPath(GetConfiguredStorageRoot()); };
            actionRow.Controls.Add(storageOpenButton);

            var help = new SoftPanel();
            help.Dock = DockStyle.Fill;
            help.Margin = new Padding(0, 10, 0, 10);
            help.Padding = new Padding(16);
            help.FillColor = Color.White;
            help.BorderColor = cardBorder;
            layout.Controls.Add(help, 1, 2);

            var helpLayout = new TableLayoutPanel();
            helpLayout.Dock = DockStyle.Fill;
            helpLayout.BackColor = Color.White;
            helpLayout.ColumnCount = 1;
            helpLayout.RowCount = 2;
            helpLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
            helpLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            help.Controls.Add(helpLayout);

            helpTitle = new Label();
            helpTitle.Text = "상세 안내";
            helpTitle.ForeColor = ink;
            helpTitle.Font = new Font(UiFont, 11.3f, FontStyle.Bold);
            helpTitle.Dock = DockStyle.Fill;
            helpTitle.TextAlign = ContentAlignment.MiddleLeft;
            helpLayout.Controls.Add(helpTitle, 0, 0);

            helpBody = new TextBox();
            helpBody.Text = "";
            helpBody.ForeColor = muted;
            helpBody.BackColor = Color.White;
            helpBody.Font = new Font(UiFont, 9.0f);
            helpBody.Dock = DockStyle.Fill;
            helpBody.Multiline = true;
            helpBody.ReadOnly = true;
            helpBody.WordWrap = true;
            helpBody.BorderStyle = BorderStyle.None;
            helpBody.ScrollBars = ScrollBars.None;
            helpBody.TabStop = false;
            helpLayout.Controls.Add(helpBody, 0, 1);

            var logPanel = new SoftPanel();
            logPanel.Dock = DockStyle.Fill;
            logPanel.Padding = new Padding(12);
            logPanel.FillColor = Color.FromArgb(28, 33, 39);
            logPanel.BorderColor = Color.FromArgb(43, 50, 58);
            layout.Controls.Add(logPanel, 0, 3);
            layout.SetColumnSpan(logPanel, 2);

            var logLayout = new TableLayoutPanel();
            logLayout.Dock = DockStyle.Fill;
            logLayout.BackColor = Color.FromArgb(28, 33, 39);
            logLayout.ColumnCount = 1;
            logLayout.RowCount = 2;
            logLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
            logLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            logPanel.Controls.Add(logLayout);

            var logTitle = new Label();
            logTitle.Text = "실행 로그";
            logTitle.ForeColor = Color.White;
            logTitle.Font = new Font(UiFont, 9.0f, FontStyle.Bold);
            logTitle.Dock = DockStyle.Fill;
            logTitle.TextAlign = ContentAlignment.MiddleLeft;
            logLayout.Controls.Add(logTitle, 0, 0);

            logBox = new TextBox();
            logBox.Multiline = true;
            logBox.ReadOnly = true;
            logBox.ScrollBars = ScrollBars.None;
            logBox.BackColor = Color.FromArgb(28, 33, 39);
            logBox.ForeColor = Color.FromArgb(226, 232, 238);
            logBox.BorderStyle = BorderStyle.None;
            logBox.Font = new Font("Consolas", 8.6f);
            logBox.Dock = DockStyle.Fill;
            logLayout.Controls.Add(logBox, 0, 1);
        }

        private Control CreateMetricCard(string title, string value, string description)
        {
            var card = new SoftPanel();
            card.Dock = DockStyle.Fill;
            card.Margin = new Padding(0, 0, 8, 0);
            card.Padding = new Padding(12);
            card.FillColor = Color.White;
            card.BorderColor = cardBorder;

            var content = new TableLayoutPanel();
            content.Dock = DockStyle.Fill;
            content.BackColor = Color.White;
            content.ColumnCount = 1;
            content.RowCount = 3;
            content.RowStyles.Add(new RowStyle(SizeType.Absolute, 20));
            content.RowStyles.Add(new RowStyle(SizeType.Absolute, 30));
            content.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            card.Controls.Add(content);

            var titleLabel = new Label();
            titleLabel.Text = title;
            titleLabel.ForeColor = muted;
            titleLabel.Font = new Font(UiFont, 8.0f, FontStyle.Bold);
            titleLabel.Dock = DockStyle.Fill;
            titleLabel.AutoEllipsis = true;
            titleLabel.BackColor = Color.White;
            content.Controls.Add(titleLabel, 0, 0);

            var valueLabel = new Label();
            valueLabel.Text = value;
            valueLabel.ForeColor = ink;
            valueLabel.Font = new Font(UiFont, title == "저장소" ? 11.4f : 13.1f, FontStyle.Bold);
            valueLabel.Dock = DockStyle.Fill;
            valueLabel.AutoEllipsis = true;
            valueLabel.BackColor = Color.White;
            if (title == "저장소")
            {
                storageMetricValue = valueLabel;
            }
            content.Controls.Add(valueLabel, 0, 1);

            var descLabel = new Label();
            descLabel.Text = description;
            descLabel.ForeColor = muted;
            descLabel.Font = new Font(UiFont, 8.0f);
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
            button.Font = new Font(UiFont, 9.0f, FontStyle.Bold);
            button.ForeColor = textColor;
            button.BackColor = fill;
            button.Size = new Size(176, 44);
            button.FlatAppearance.BorderSize = 1;
            button.FlatAppearance.BorderColor = fill;
            button.FlatAppearance.MouseOverBackColor = fill;
            button.FlatAppearance.MouseDownBackColor = ControlPaint.Dark(fill, 0.05f);
            button.Cursor = Cursors.Hand;
            button.MinimumSize = new Size(112, 44);
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
            primaryButton.FlatAppearance.BorderColor = primaryButton.BackColor;
            primaryButton.FlatAppearance.MouseOverBackColor = primaryButton.BackColor;
            primaryButton.FlatAppearance.MouseDownBackColor = ControlPaint.Dark(primaryButton.BackColor, 0.05f);
            primaryButton.AccessibleDescription = action.Description;
            UpdateStorageActionVisibility(action.Task);

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
            helpTitle.Text = action.Title + " 안내";
            SetMultilineText(helpBody, GetHelpText(action.Task));
        }

        private void UpdateStorageActionVisibility(string task)
        {
            bool show = string.Equals(task, "server-setup", StringComparison.OrdinalIgnoreCase);
            if (secondaryButton != null)
            {
                secondaryButton.Visible = show;
            }
            if (storageOpenButton != null)
            {
                storageOpenButton.Visible = show;
            }
        }

        private void FocusSelectedNav()
        {
            if (navList == null) return;
            foreach (Control c in navList.Controls)
            {
                if (string.Equals(c.Tag as string, selectedTask, StringComparison.OrdinalIgnoreCase))
                {
                    c.Focus();
                    return;
                }
            }
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
            if (action.Task == "clone-rpi4")
            {
                return "주의: 새 RPi4 client 생성, 기존 성공 client는 보호";
            }
            return "안전: 읽기 전용 확인 작업";
        }

        private string GetPrimaryButtonText(ActionDefinition action)
        {
            switch (action.Task)
            {
                case "status": return "상태 확인 실행";
                case "server-setup": return "서버 PC 준비";
                case "lite-provider-start": return "서비스 시작";
                case "prepare-sd": return "OS SD 작성";
                case "clone-rpi4": return "새 RPi4 복제 시작";
                case "zero2w-gadget-sd": return "gadget SD 패치";
                case "docs": return "도움말 열기";
                default: return "실행";
            }
        }

        private string GetHelpText(string task)
        {
            if (task == "prepare-sd")
            {
                return "RPi4 부팅용 Raspberry Pi OS SD를 만듭니다. 버튼을 누르면 현재 연결된 디스크 목록을 보여주고, 사용자가 선택한 디스크에만 Raspberry Pi OS Lite 64-bit Trixie 2026-04-21 이미지를 씁니다.\n\nboot/system 디스크, 미디어 없음, USB가 아닌 디스크, 64GB 초과 디스크는 선택할 수 없습니다.\n\n다음: RPi4를 이 OS SD로 부팅하면 관리자 서비스가 MAC에 임시 IP를 주고, OS가 시리얼/MAC/EEPROM boot order를 자동 보고합니다.";
            }

            switch (task)
            {
                case "status":
                    return "처음에는 이 버튼을 누르세요. 현재 설정된 저장소, 이더넷 IP, 공유기 연결, 서비스 포트 상태를 읽기 전용으로 확인합니다.\n\n정상이면 부팅 서비스 시작 또는 새 RPi4 등록/복제로 넘어갑니다.";
                case "server-setup":
                    return "서버 PC를 네트워크 부팅용으로 맞춥니다. 저장소 설정에서 선택한 위치 아래에 tftp/rootfs/tools 구조를 확인하고 유선 이더넷을 10.73.0.10으로 적용합니다.\n\n다음: 부팅 서비스 시작을 누릅니다.";
                case "lite-provider-start":
                    return "RPi4가 네트워크 부팅 요청을 보낼 때 응답할 DHCP/TFTP/NFS 서비스를 시작합니다.\n\n다음: 상태 확인을 누르고 새 RPi4 전원을 다시 넣습니다.";
                case "clone-rpi4":
                    return "새 Raspberry Pi 4를 등록하고 현재 성공한 bootfs/rootfs에서 복제합니다.\n\nOS SD 첫 부팅 리포트가 있으면 시리얼/MAC/IP가 자동으로 채워집니다. 값이 맞는지만 확인하고 기기 번호를 정하세요.\n\n자동 반영:\n- " + GetConfiguredTftpRoot() + "\\<serial>\n- " + GetConfiguredRootfsRoot() + "\\<serial>\n- hostname\n- /etc/rpi-netboot/client.json\n- machine-id/SSH host key 초기화";
                case "zero2w-gadget-sd":
                    return "Zero 2 W는 네트워크 부팅 대상이 아닙니다. S:의 Raspberry Pi OS boot 파티션을 USB Ethernet gadget용으로 패치합니다.\n\n연결: PWR IN이 아니라 mini HDMI 옆 USB data 포트를 PC에 꽂습니다.";
                case "docs":
                    return "새 RPi4 등록/복제 Runbook과 운영 문서를 엽니다.";
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

            if (action.Task == "clone-rpi4")
            {
                using (var dialog = new CloneRpi4Dialog(GetConfiguredTftpRoot(), GetConfiguredRootfsRoot(), LoadLatestProvisionCandidate()))
                {
                    if (dialog.ShowDialog(this) != DialogResult.OK) return;
                    pendingCloneRequest = dialog.Request;
                }
            }

            if (action.RequiresAdmin && !IsCurrentProcessAdmin())
            {
                LaunchAdmin(action.Task);
                return;
            }

            if (action.Task == "prepare-sd")
            {
                using (var dialog = new SdImageWriteDialog())
                {
                    if (dialog.ShowDialog(this) != DialogResult.OK) return;
                    pendingSdImageWriteRequest = dialog.Request;
                }
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
            if (action.Task == "clone-rpi4")
            {
                pendingCloneRequest = null;
            }
            if (action.Task == "prepare-sd")
            {
                pendingSdImageWriteRequest = null;
            }
        }

        private string BuildPowerShellArguments(ActionDefinition action)
        {
            string command = BuildPowerShellCommand(action);
            return BuildPowerShellArguments(command);
        }

        private string BuildPowerShellArguments(string command)
        {
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
                case "prepare-sd":
                    if (pendingSdImageWriteRequest == null) throw new InvalidOperationException("OS SD target disk is missing.");
                    return commandPrefix + "& " + PsSingle(scriptPath) +
                        " -Task prepare-sd -SdDiskNumber " + pendingSdImageWriteRequest.DiskNumber.ToString() +
                        " -Yes 3>&1 4>&1 5>&1 6>&1";
                case "zero2w-gadget-sd":
                    toolPath = Path.Combine(projectRoot, "tools", "zero2w-gadget-sd.ps1");
                    return commandPrefix + "& " + PsSingle(toolPath) + " apply -DriveLetter S -Yes 3>&1 4>&1 5>&1 6>&1";
                case "clone-rpi4":
                    if (pendingCloneRequest == null) throw new InvalidOperationException("Clone request is missing.");
                    toolPath = Path.Combine(projectRoot, "tools", "clone-rpi4-client.ps1");
                    string configPath = Path.Combine(projectRoot, "lab-10.73.json");
                    string cloneCommand = commandPrefix + "& " + PsSingle(toolPath) +
                        " clone -Config " + PsSingle(configPath) +
                        " -GoldenSerial d80c0b88" +
                        " -DeviceId " + PsSingle(pendingCloneRequest.DeviceId) +
                        " -Serial " + PsSingle(pendingCloneRequest.Serial) +
                        " -Mac " + PsSingle(pendingCloneRequest.Mac);
                    if (!string.IsNullOrWhiteSpace(pendingCloneRequest.Ip))
                    {
                        cloneCommand += " -Ip " + PsSingle(pendingCloneRequest.Ip);
                    }
                    return cloneCommand + " 3>&1 4>&1 5>&1 6>&1";
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
            if (action.Task == "prepare-sd" && pendingSdImageWriteRequest != null)
            {
                return "RPi4 OS SD를 만듭니다.\n\n대상: " + pendingSdImageWriteRequest.Summary +
                       "\n실행 내용: Raspberry Pi OS Lite 64-bit Trixie 2026-04-21 이미지 쓰기 + 첫 부팅 자동 등록 리포터 적용" +
                       "\n주의: 선택한 디스크 전체 내용 삭제" +
                       "\n\n이 SD로 Pi를 부팅하면 관리자가 시리얼/MAC/EEPROM boot order를 자동 수집합니다. 계속하려면 [예]를 누르세요.";
            }

            switch (action.Task)
            {
                case "server-setup":
                    return "서버 PC 준비를 실행합니다.\n\n변경 대상:\n- 유선 이더넷 IP: 10.73.0.10\n- 저장소 구조: " + GetConfiguredTftpRoot() + ", " + GetConfiguredRootfsRoot() + ", " + Path.Combine(GetConfiguredStorageRoot(), "downloads") + "\n- TFTP 파일 동기화와 방화벽 규칙\n\n선택한 저장소가 맞고 이 PC가 서버 PC이면 [예]를 누르세요.";
                case "lite-provider-start":
                    return "부팅 서비스를 시작합니다.\n\n실행 내용:\n- DHCP/TFTP 서버 시작\n- rootfs 서비스 시작\n- DHCP/TFTP/NFS 방화벽 규칙 확인\n\nPi가 다음 DHCP에서 예약 IP를 받게 됩니다. 계속하려면 [예]를 누르세요.";
                case "prepare-sd":
                    return "RPi4 OS SD를 만듭니다.\n\n실행 내용: Raspberry Pi OS Lite 64-bit Trixie 2026-04-21 이미지 쓰기 + 첫 부팅 자동 등록 리포터 적용\n주의: 선택한 디스크 전체 내용 삭제\n\n계속하려면 [예]를 누르세요.";
                case "zero2w-gadget-sd":
                    return "Zero 2 W USB gadget SD를 패치합니다.\n\n대상: S:\n변경 파일: config.txt, cmdline.txt, user-data, ssh marker\n주의: Zero 2 W는 SD로 부팅합니다. RPi4 네트워크 부팅 대상에 넣지 않습니다.\n\nS:가 Zero 2 W용 OS SD이면 [예]를 누르세요.";
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
            if (storageOpenButton != null) storageOpenButton.Enabled = !busy;
            foreach (Control c in navList.Controls) c.Enabled = !busy;
            statusLabel.Text = status;
            statusLabel.BackColor = busy ? Color.FromArgb(255, 246, 220) : tealSoft;
            statusLabel.ForeColor = busy ? amber : teal;
            if (!busy && storageMetricValue != null)
            {
                storageMetricValue.Text = GetStorageDisplayRoot();
            }
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
            if (logBox.ScrollBars != ScrollBars.Vertical && logBox.Lines.Length > 8)
            {
                logBox.ScrollBars = ScrollBars.Vertical;
            }
        }

        private string GetConfigPath()
        {
            return Path.Combine(projectRoot, "lab-10.73.json");
        }

        private string GetStorageDisplayRoot()
        {
            string root = GetConfiguredStorageRoot();
            return root.Length > 18 ? root.Substring(0, 18) + "..." : root;
        }

        private string GetConfiguredStorageRoot()
        {
            string value = ReadJsonString(GetConfigPath(), "project_root");
            if (string.IsNullOrWhiteSpace(value)) value = "D:\\";
            return NormalizeStorageRoot(value);
        }

        private string GetConfiguredTftpRoot()
        {
            string value = ReadJsonString(GetConfigPath(), "tftp_root");
            if (!string.IsNullOrWhiteSpace(value)) return value.TrimEnd('\\');
            return Path.Combine(GetConfiguredStorageRoot(), "tftp");
        }

        private string GetConfiguredRootfsRoot()
        {
            string value = ReadJsonString(GetConfigPath(), "nfs_root");
            if (!string.IsNullOrWhiteSpace(value)) return value.TrimEnd('\\');
            return Path.Combine(GetConfiguredStorageRoot(), "rootfs");
        }

        private string ReadJsonString(string path, string property)
        {
            try
            {
                if (!File.Exists(path)) return "";
                string text = File.ReadAllText(path, Encoding.UTF8);
                return ReadJsonField(text, property);
            }
            catch
            {
                return "";
            }
        }

        private string ReadJsonField(string text, string property)
        {
            Match match = Regex.Match(text ?? "", "\"" + Regex.Escape(property) + "\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");
            if (!match.Success) return "";
            return Regex.Unescape(match.Groups[1].Value);
        }

        private ProvisionCandidate LoadLatestProvisionCandidate()
        {
            try
            {
                string path = Path.Combine(Path.Combine(GetConfiguredStorageRoot(), "logs"), "rpi-provisioning.jsonl");
                if (!File.Exists(path)) return null;
                string[] lines = File.ReadAllLines(path, Encoding.UTF8);
                for (int i = lines.Length - 1; i >= 0; i--)
                {
                    string line = lines[i];
                    string serial = ReadJsonField(line, "serial");
                    string mac = ReadJsonField(line, "mac");
                    if (string.IsNullOrWhiteSpace(serial) && string.IsNullOrWhiteSpace(mac)) continue;
                    return new ProvisionCandidate
                    {
                        ReceivedAt = ReadJsonField(line, "received_at"),
                        Serial = serial,
                        Mac = mac,
                        Ip = ReadJsonField(line, "ip"),
                        Model = ReadJsonField(line, "model"),
                        BootOrder = ReadJsonField(line, "boot_order")
                    };
                }
            }
            catch
            {
            }
            return null;
        }

        private string NormalizeStorageRoot(string value)
        {
            string full = Path.GetFullPath((value ?? "").Trim());
            string trimmed = full.TrimEnd('\\', '/');
            if (Regex.IsMatch(trimmed, "^[A-Za-z]:$")) return trimmed + "\\";
            return trimmed;
        }

        private void ChooseStorageRoot()
        {
            if (isRunning) return;
            using (var dialog = new FolderBrowserDialog())
            {
                dialog.Description = "TFTP, rootfs, downloads, tools 폴더를 둘 저장소를 선택하세요.";
                dialog.ShowNewFolderButton = true;
                string current = GetConfiguredStorageRoot();
                if (Directory.Exists(current)) dialog.SelectedPath = current;
                if (dialog.ShowDialog(this) != DialogResult.OK) return;

                string selected = NormalizeStorageRoot(dialog.SelectedPath);
                DialogResult result = MessageBox.Show(
                    "저장소를 다음 위치로 설정합니다.\n\n" + selected + "\n\n이 아래에 tftp, rootfs, downloads, logs, tools 폴더를 사용합니다.",
                    "저장소 설정",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Information,
                    MessageBoxDefaultButton.Button1);
                if (result != DialogResult.Yes) return;

                RunPowerShell("저장소 설정", BuildPowerShellArguments(BuildStorageConfigCommand(selected)));
            }
        }

        private string BuildStorageConfigCommand(string storageRoot)
        {
            string configPath = GetConfigPath();
            string tftpRoot = Path.Combine(storageRoot, "tftp");
            string rootfsRoot = Path.Combine(storageRoot, "rootfs");
            string downloads = Path.Combine(storageRoot, "downloads");
            string logs = Path.Combine(storageRoot, "logs");
            string tools = Path.Combine(storageRoot, "tools");
            string iscsiRoot = Path.Combine(storageRoot, "iscsi");

            return "$enc=New-Object System.Text.UTF8Encoding -ArgumentList $false; " +
                   "[Console]::OutputEncoding=$enc; $OutputEncoding=$enc; " +
                   "$ProgressPreference='SilentlyContinue'; " +
                   "$config=" + PsSingle(configPath) + "; " +
                   "$root=" + PsSingle(storageRoot) + "; " +
                   "$cfg=if(Test-Path -LiteralPath $config){Get-Content -LiteralPath $config -Raw -Encoding UTF8|ConvertFrom-Json}else{[pscustomobject]@{name='rpi-netboot-windows';method='windows-lite-nfs';server_ip='10.73.0.10';router_ip='10.73.0.1';dns_server='10.73.0.1';subnet_mask='255.255.255.0';dhcp_start='10.73.0.100';dhcp_end='10.73.0.199';nfs_alias='/rpi';vhdx_size_gb=32;clients=@()}}; " +
                   "function Set-Prop($o,$n,$v){if($o.PSObject.Properties[$n]){$o.$n=$v}else{$o|Add-Member -NotePropertyName $n -NotePropertyValue $v}}; " +
                   "Set-Prop $cfg 'project_root' $root; " +
                   "Set-Prop $cfg 'tftp_root' " + PsSingle(tftpRoot) + "; " +
                   "Set-Prop $cfg 'nfs_root' " + PsSingle(rootfsRoot) + "; " +
                   "Set-Prop $cfg 'iscsi_root' " + PsSingle(iscsiRoot) + "; " +
                   "foreach($path in @($root," + PsSingle(tftpRoot) + "," + PsSingle(rootfsRoot) + "," + PsSingle(downloads) + "," + PsSingle(logs) + "," + PsSingle(tools) + ")){New-Item -ItemType Directory -Force -Path $path|Out-Null}; " +
                   "$cfg|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $config -Encoding UTF8; " +
                   "Write-Output ('저장소 설정 완료: ' + $root) 3>&1 4>&1 5>&1 6>&1";
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
            string selfExe = Application.ExecutablePath;
            if (!File.Exists(selfExe))
            {
                MessageBox.Show("실행 파일을 찾을 수 없습니다.\n" + selfExe, "관리자 권한 필요", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            DialogResult result = MessageBox.Show(
                "이 작업은 관리자 권한이 필요합니다.\n\n관리자 권한으로 다시 열까요?",
                "관리자 권한 필요",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Information,
                MessageBoxDefaultButton.Button1);
            if (result != DialogResult.Yes) return;

            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = selfExe,
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
                g.DrawRectangle(p, rect.Left + 11, rect.Top + 13, 20, 15);
                g.DrawLine(p, rect.Left + 21, rect.Top + 28, rect.Left + 21, rect.Top + 35);
                g.DrawLine(p, rect.Left + 15, rect.Top + 35, rect.Left + 28, rect.Top + 35);
            }
            using (Brush b = new SolidBrush(Color.FromArgb(255, 217, 122)))
            {
                g.FillEllipse(b, rect.Left + 8, rect.Top + 7, 6, 6);
                g.FillEllipse(b, rect.Left + 28, rect.Top + 7, 6, 6);
                g.FillEllipse(b, rect.Left + 18, rect.Top + 4, 6, 6);
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

    internal sealed class CloneRpi4Request
    {
        public string DeviceId;
        public string Serial;
        public string Mac;
        public string Ip;
    }

    internal sealed class ProvisionCandidate
    {
        public string ReceivedAt;
        public string Serial;
        public string Mac;
        public string Ip;
        public string Model;
        public string BootOrder;
    }

    internal sealed class SdImageWriteRequest
    {
        public int DiskNumber;
        public string Summary;
    }

    internal sealed class SdDiskRow
    {
        private const UInt64 MaxSafeBytes = 64UL * 1024UL * 1024UL * 1024UL;

        public int DiskNumber { get; set; }
        public string FriendlyName { get; set; }
        public string BusType { get; set; }
        public string MediaType { get; set; }
        public string PartitionStyle { get; set; }
        public UInt64 SizeBytes { get; set; }
        public bool IsBoot { get; set; }
        public bool IsSystem { get; set; }
        public string Volumes { get; set; }

        public string Disk
        {
            get { return "PhysicalDrive" + DiskNumber.ToString(); }
        }

        public string Size
        {
            get { return FormatBytes(SizeBytes); }
        }

        public bool IsSafe
        {
            get
            {
                return !IsBoot &&
                       !IsSystem &&
                       SizeBytes > 0 &&
                       SizeBytes <= MaxSafeBytes &&
                       string.Equals(BusType, "USB", StringComparison.OrdinalIgnoreCase);
            }
        }

        public string Safety
        {
            get
            {
                if (IsBoot || IsSystem) return "차단: Windows boot/system";
                if (SizeBytes == 0) return "차단: 미디어 없음";
                if (!string.Equals(BusType, "USB", StringComparison.OrdinalIgnoreCase)) return "차단: USB 아님";
                if (SizeBytes > MaxSafeBytes) return "차단: 64GB 초과";
                return "선택 가능";
            }
        }

        public string Summary
        {
            get
            {
                string volumes = string.IsNullOrWhiteSpace(Volumes) ? "볼륨 없음" : Volumes;
                return Disk + " / " + FriendlyName + " / " + BusType + " / " + Size + " / " + volumes;
            }
        }

        private static string FormatBytes(UInt64 value)
        {
            const double KB = 1024.0;
            const double MB = KB * 1024.0;
            const double GB = MB * 1024.0;
            const double TB = GB * 1024.0;
            if (value >= (UInt64)TB) return (value / TB).ToString("0.00") + " TB";
            if (value >= (UInt64)GB) return (value / GB).ToString("0.00") + " GB";
            if (value >= (UInt64)MB) return (value / MB).ToString("0.00") + " MB";
            if (value >= (UInt64)KB) return (value / KB).ToString("0.00") + " KB";
            return value.ToString() + " B";
        }
    }

    internal sealed class SdImageWriteDialog : Form
    {
        private static readonly string UiFont = UiFonts.Family;
        private readonly DataGridView grid;
        private readonly Label messageLabel;
        private readonly Button okButton;
        private List<SdDiskRow> rows = new List<SdDiskRow>();

        public SdImageWriteRequest Request { get; private set; }

        public SdImageWriteDialog()
        {
            Text = "OS SD 대상 디스크 선택";
            StartPosition = FormStartPosition.CenterParent;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ClientSize = new Size(860, 520);
            BackColor = Color.FromArgb(245, 247, 248);
            Font = new Font(UiFont, 9.0f);

            var root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.Padding = new Padding(22);
            root.ColumnCount = 1;
            root.RowCount = 4;
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 78));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 58));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 58));
            Controls.Add(root);

            var header = new Panel();
            header.Dock = DockStyle.Fill;
            root.Controls.Add(header, 0, 0);

            var title = new Label();
            title.Text = "Raspberry Pi OS 이미지를 쓸 디스크 선택";
            title.ForeColor = Color.FromArgb(26, 33, 30);
            title.Font = new Font(UiFont, 15.5f, FontStyle.Bold);
            title.Dock = DockStyle.Top;
            title.Height = 32;
            header.Controls.Add(title);

            var subtitle = new Label();
            subtitle.Text = "선택한 전체 디스크가 지워집니다. 드라이브 문자보다 PhysicalDrive 번호를 기준으로 확인하세요.";
            subtitle.ForeColor = Color.FromArgb(82, 96, 88);
            subtitle.Font = new Font(UiFont, 8.8f);
            subtitle.Dock = DockStyle.Bottom;
            subtitle.Height = 34;
            header.Controls.Add(subtitle);

            grid = new DataGridView();
            grid.Dock = DockStyle.Fill;
            grid.ReadOnly = true;
            grid.AllowUserToAddRows = false;
            grid.AllowUserToDeleteRows = false;
            grid.AllowUserToResizeRows = false;
            grid.RowHeadersVisible = false;
            grid.MultiSelect = false;
            grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            grid.AutoGenerateColumns = false;
            grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
            grid.BackgroundColor = Color.White;
            grid.BorderStyle = BorderStyle.FixedSingle;
            grid.SelectionChanged += delegate { UpdateSelectionMessage(); };
            AddColumn("Disk", "디스크", 88);
            AddColumn("FriendlyName", "이름", 190);
            AddColumn("BusType", "버스", 70);
            AddColumn("Size", "크기", 82);
            AddColumn("PartitionStyle", "파티션", 78);
            AddColumn("Volumes", "볼륨", 210);
            AddColumn("Safety", "상태", 130);
            root.Controls.Add(grid, 0, 1);

            messageLabel = new Label();
            messageLabel.Dock = DockStyle.Fill;
            messageLabel.TextAlign = ContentAlignment.MiddleLeft;
            messageLabel.Padding = new Padding(10, 0, 10, 0);
            messageLabel.ForeColor = Color.FromArgb(180, 35, 24);
            messageLabel.BackColor = Color.FromArgb(255, 244, 232);
            root.Controls.Add(messageLabel, 0, 2);

            var buttons = new FlowLayoutPanel();
            buttons.Dock = DockStyle.Fill;
            buttons.FlowDirection = FlowDirection.RightToLeft;
            buttons.WrapContents = false;
            root.Controls.Add(buttons, 0, 3);

            okButton = CreateDialogButton("OS 이미지 쓰기", Color.FromArgb(168, 88, 20), Color.White, 162);
            okButton.Click += delegate { Submit(); };
            buttons.Controls.Add(okButton);
            AcceptButton = okButton;

            var cancel = CreateDialogButton("취소", Color.FromArgb(237, 241, 236), Color.FromArgb(26, 33, 30), 100);
            cancel.Click += delegate { DialogResult = DialogResult.Cancel; Close(); };
            buttons.Controls.Add(cancel);
            CancelButton = cancel;

            var refresh = CreateDialogButton("새로고침", Color.FromArgb(237, 241, 236), Color.FromArgb(26, 33, 30), 110);
            refresh.Click += delegate { ReloadRows(); };
            buttons.Controls.Add(refresh);

            ReloadRows();
        }

        private void AddColumn(string property, string header, int fillWeight)
        {
            var column = new DataGridViewTextBoxColumn();
            column.DataPropertyName = property;
            column.HeaderText = header;
            column.FillWeight = fillWeight;
            column.SortMode = DataGridViewColumnSortMode.NotSortable;
            grid.Columns.Add(column);
        }

        private Button CreateDialogButton(string text, Color fill, Color textColor, int width)
        {
            var button = new Button();
            button.Text = text;
            button.FlatStyle = FlatStyle.Flat;
            button.FlatAppearance.BorderSize = 0;
            button.BackColor = fill;
            button.ForeColor = textColor;
            button.Font = new Font(UiFont, 9.0f, FontStyle.Bold);
            button.Size = new Size(width, 42);
            button.Margin = new Padding(8, 6, 0, 6);
            button.Cursor = Cursors.Hand;
            return button;
        }

        private void ReloadRows()
        {
            try
            {
                rows = LoadDiskRows();
                grid.DataSource = null;
                grid.DataSource = rows;
                StyleRows();
                SelectDefaultRow();
                UpdateSelectionMessage();
            }
            catch (Exception ex)
            {
                rows = new List<SdDiskRow>();
                grid.DataSource = null;
                messageLabel.Text = "디스크 목록을 읽지 못했습니다: " + ex.Message;
                okButton.Enabled = false;
            }
        }

        private void StyleRows()
        {
            foreach (DataGridViewRow row in grid.Rows)
            {
                var disk = row.DataBoundItem as SdDiskRow;
                if (disk == null) continue;
                if (!disk.IsSafe)
                {
                    row.DefaultCellStyle.ForeColor = Color.FromArgb(120, 124, 130);
                    row.DefaultCellStyle.BackColor = Color.FromArgb(248, 248, 248);
                }
            }
        }

        private void SelectDefaultRow()
        {
            if (grid.Rows.Count == 0) return;
            grid.ClearSelection();
            int index = 0;
            for (int i = 0; i < rows.Count; i++)
            {
                if (rows[i].IsSafe)
                {
                    index = i;
                    break;
                }
            }
            grid.Rows[index].Selected = true;
            grid.CurrentCell = grid.Rows[index].Cells[0];
        }

        private void UpdateSelectionMessage()
        {
            var selected = GetSelectedRow();
            if (selected == null)
            {
                messageLabel.Text = "대상 디스크를 선택하세요.";
                okButton.Enabled = false;
                return;
            }

            okButton.Enabled = selected.IsSafe;
            if (selected.IsSafe)
            {
                messageLabel.ForeColor = Color.FromArgb(116, 58, 0);
                messageLabel.Text = "선택됨: " + selected.Summary + "  -  Raspberry Pi OS를 쓰며 디스크 전체가 지워집니다.";
            }
            else
            {
                messageLabel.ForeColor = Color.FromArgb(180, 35, 24);
                messageLabel.Text = selected.Summary + "  -  " + selected.Safety;
            }
        }

        private SdDiskRow GetSelectedRow()
        {
            if (grid.CurrentRow != null)
            {
                return grid.CurrentRow.DataBoundItem as SdDiskRow;
            }
            if (grid.SelectedRows.Count > 0)
            {
                return grid.SelectedRows[0].DataBoundItem as SdDiskRow;
            }
            return null;
        }

        private void Submit()
        {
            var selected = GetSelectedRow();
            if (selected == null || !selected.IsSafe)
            {
                UpdateSelectionMessage();
                return;
            }
            Request = new SdImageWriteRequest
            {
                DiskNumber = selected.DiskNumber,
                Summary = selected.Summary
            };
            DialogResult = DialogResult.OK;
            Close();
        }

        private static List<SdDiskRow> LoadDiskRows()
        {
            string script = @"
$enc = New-Object System.Text.UTF8Encoding -ArgumentList $false
[Console]::OutputEncoding = $enc
$OutputEncoding = $enc
$ErrorActionPreference = 'Stop'
$volumesByDisk = @{}
foreach ($partition in Get-Partition -ErrorAction SilentlyContinue) {
    if ($partition.DriveLetter) {
        $key = [string]$partition.DiskNumber
        if (-not $volumesByDisk.ContainsKey($key)) { $volumesByDisk[$key] = @() }
        $volume = Get-Volume -DriveLetter $partition.DriveLetter -ErrorAction SilentlyContinue
        $label = if ($volume) { [string]$volume.FileSystemLabel } else { '' }
        $fs = if ($volume) { [string]$volume.FileSystem } else { '' }
        $volumesByDisk[$key] += (('{0}:{1}:{2}' -f $partition.DriveLetter, $label, $fs).TrimEnd(':'))
    }
}
Get-Disk | Sort-Object Number | ForEach-Object {
    $key = [string]$_.Number
    $volumes = if ($volumesByDisk.ContainsKey($key)) { $volumesByDisk[$key] -join ', ' } else { '' }
    $fields = @(
        [string]$_.Number,
        [string]$_.FriendlyName,
        [string]$_.BusType,
        [string]$_.MediaType,
        [string]$_.PartitionStyle,
        [string][UInt64]$_.Size,
        [string]$_.IsBoot,
        [string]$_.IsSystem,
        [string]$volumes
    )
    (($fields | ForEach-Object { ([string]$_).Replace(""`t"", "" "").Replace(""`r"", "" "").Replace(""`n"", "" "") }) -join ""`t"")
}
";

            var psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand " +
                            Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
            psi.UseShellExecute = false;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.CreateNoWindow = true;
            psi.StandardOutputEncoding = Encoding.UTF8;
            psi.StandardErrorEncoding = Encoding.UTF8;

            using (var process = Process.Start(psi))
            {
                if (!process.WaitForExit(12000))
                {
                    try { process.Kill(); } catch { }
                    throw new InvalidOperationException("Get-Disk timed out.");
                }
                string output = process.StandardOutput.ReadToEnd();
                string error = process.StandardError.ReadToEnd();
                if (process.ExitCode != 0)
                {
                    throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? "Get-Disk failed." : error.Trim());
                }
                return ParseDiskRows(output);
            }
        }

        private static List<SdDiskRow> ParseDiskRows(string output)
        {
            var result = new List<SdDiskRow>();
            string[] lines = (output ?? "").Replace("\r\n", "\n").Split(new char[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (string raw in lines)
            {
                string line = raw.TrimEnd('\r');
                if (line.Trim().Length == 0) continue;
                string[] parts = line.Split(new char[] { '\t' });
                if (parts.Length < 9) continue;

                int number;
                UInt64 size;
                if (!Int32.TryParse(parts[0], out number)) continue;
                if (!UInt64.TryParse(parts[5], out size)) size = 0;

                result.Add(new SdDiskRow
                {
                    DiskNumber = number,
                    FriendlyName = parts[1],
                    BusType = parts[2],
                    MediaType = parts[3],
                    PartitionStyle = parts[4],
                    SizeBytes = size,
                    IsBoot = ParseBool(parts[6]),
                    IsSystem = ParseBool(parts[7]),
                    Volumes = parts[8]
                });
            }
            return result;
        }

        private static bool ParseBool(string value)
        {
            return string.Equals(value, "True", StringComparison.OrdinalIgnoreCase) ||
                   string.Equals(value, "1", StringComparison.OrdinalIgnoreCase);
        }
    }

    internal sealed class CloneRpi4Dialog : Form
    {
        private static readonly string UiFont = UiFonts.Family;
        private readonly TextBox deviceIdBox;
        private readonly TextBox serialBox;
        private readonly TextBox macBox;
        private readonly TextBox ipBox;
        private readonly Label errorLabel;

        public CloneRpi4Request Request { get; private set; }

        public CloneRpi4Dialog(string tftpRoot, string rootfsRoot, ProvisionCandidate candidate)
        {
            Text = "새 RPi4 등록/복제";
            StartPosition = FormStartPosition.CenterParent;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ClientSize = new Size(600, 470);
            BackColor = Color.FromArgb(245, 247, 248);
            Font = new Font(UiFont, 9.0f);

            var root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.Padding = new Padding(24);
            root.ColumnCount = 1;
            root.RowCount = 5;
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 90));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 208));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 66));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 58));
            Controls.Add(root);

            var title = new Label();
            title.Text = "새 Raspberry Pi 4 만들기";
            title.ForeColor = Color.FromArgb(26, 33, 30);
            title.Font = new Font(UiFont, 16.0f, FontStyle.Bold);
            title.Dock = DockStyle.Top;
            title.Height = 34;
            root.Controls.Add(title, 0, 0);

            var subtitle = new Label();
            subtitle.Text = "기기 번호를 기준으로 bootfs, rootfs, hostname, 내부 설정 파일을 만듭니다.";
            subtitle.ForeColor = Color.FromArgb(82, 96, 88);
            subtitle.Font = new Font(UiFont, 8.8f);
            subtitle.Dock = DockStyle.Fill;
            subtitle.Top = 38;
            subtitle.Padding = new Padding(0, 38, 0, 0);
            root.Controls.Add(subtitle, 0, 0);
            subtitle.BringToFront();

            var fields = new TableLayoutPanel();
            fields.Dock = DockStyle.Fill;
            fields.ColumnCount = 2;
            fields.RowCount = 4;
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            for (int i = 0; i < 4; i++) fields.RowStyles.Add(new RowStyle(SizeType.Absolute, 52));
            root.Controls.Add(fields, 0, 1);

            deviceIdBox = AddField(fields, 0, "기기 번호", "rpi-001");
            serialBox = AddField(fields, 1, "RPi4 시리얼", "8자리 hex, 예: a1b2c3d4");
            macBox = AddField(fields, 2, "MAC 주소", "88:a2:9e:xx:xx:xx");
            ipBox = AddField(fields, 3, "예약 IP", "비워두면 자동 할당");
            ApplyProvisionCandidate(candidate);

            var note = new Label();
            note.Text = BuildCandidateNote(tftpRoot, rootfsRoot, candidate);
            note.ForeColor = Color.FromArgb(15, 118, 110);
            note.BackColor = Color.FromArgb(220, 244, 239);
            note.TextAlign = ContentAlignment.MiddleLeft;
            note.Padding = new Padding(14, 0, 14, 0);
            note.Dock = DockStyle.Fill;
            note.Font = new Font(UiFont, 8.2f);
            note.AutoEllipsis = true;
            root.Controls.Add(note, 0, 2);

            errorLabel = new Label();
            errorLabel.Text = "";
            errorLabel.ForeColor = Color.FromArgb(180, 35, 24);
            errorLabel.Dock = DockStyle.Fill;
            errorLabel.Padding = new Padding(2, 10, 2, 0);
            root.Controls.Add(errorLabel, 0, 3);

            var buttons = new FlowLayoutPanel();
            buttons.Dock = DockStyle.Fill;
            buttons.FlowDirection = FlowDirection.RightToLeft;
            buttons.WrapContents = false;
            root.Controls.Add(buttons, 0, 4);

            var ok = CreateDialogButton("등록 및 복제", Color.FromArgb(15, 118, 110), Color.White);
            ok.Click += delegate { Submit(); };
            buttons.Controls.Add(ok);
            AcceptButton = ok;

            var cancel = CreateDialogButton("취소", Color.FromArgb(237, 241, 236), Color.FromArgb(26, 33, 30));
            cancel.Click += delegate { DialogResult = DialogResult.Cancel; Close(); };
            buttons.Controls.Add(cancel);
            CancelButton = cancel;
        }

        private TextBox AddField(TableLayoutPanel fields, int row, string label, string placeholder)
        {
            var lab = new Label();
            lab.Text = label;
            lab.Dock = DockStyle.Fill;
            lab.TextAlign = ContentAlignment.MiddleLeft;
            lab.ForeColor = Color.FromArgb(26, 33, 30);
            lab.Font = new Font(UiFont, 9.0f, FontStyle.Bold);
            fields.Controls.Add(lab, 0, row);

            var box = new TextBox();
            box.Dock = DockStyle.Fill;
            box.Font = new Font(UiFont, 9.2f);
            box.Margin = new Padding(0, 9, 0, 8);
            box.AccessibleName = label;
            box.Text = "";
            box.Tag = placeholder;
            fields.Controls.Add(box, 1, row);
            return box;
        }

        private void ApplyProvisionCandidate(ProvisionCandidate candidate)
        {
            if (candidate == null) return;
            if (!string.IsNullOrWhiteSpace(candidate.Serial))
            {
                string serial = candidate.Serial.Trim().ToLowerInvariant();
                serialBox.Text = serial.Length > 8 ? serial.Substring(serial.Length - 8) : serial;
                if (string.IsNullOrWhiteSpace(deviceIdBox.Text) && serialBox.Text.Length >= 4)
                {
                    deviceIdBox.Text = "rpi-" + serialBox.Text.Substring(serialBox.Text.Length - 4);
                }
            }
            if (!string.IsNullOrWhiteSpace(candidate.Mac)) macBox.Text = candidate.Mac.Trim().ToLowerInvariant();
            if (!string.IsNullOrWhiteSpace(candidate.Ip)) ipBox.Text = candidate.Ip.Trim();
        }

        private string BuildCandidateNote(string tftpRoot, string rootfsRoot, ProvisionCandidate candidate)
        {
            string golden = "Golden: " + tftpRoot + "\\d80c0b88, " + rootfsRoot + "\\d80c0b88";
            if (candidate == null)
            {
                return golden + " | Waiting for OS SD provision report.";
            }

            string detected = "Detected";
            if (!string.IsNullOrWhiteSpace(candidate.Serial)) detected += " serial=" + candidate.Serial;
            if (!string.IsNullOrWhiteSpace(candidate.Mac)) detected += " mac=" + candidate.Mac;
            if (!string.IsNullOrWhiteSpace(candidate.Ip)) detected += " ip=" + candidate.Ip;
            if (!string.IsNullOrWhiteSpace(candidate.BootOrder)) detected += " boot=" + candidate.BootOrder;
            return detected + " | " + golden;
        }

        private Button CreateDialogButton(string text, Color fill, Color textColor)
        {
            var button = new Button();
            button.Text = text;
            button.FlatStyle = FlatStyle.Flat;
            button.FlatAppearance.BorderSize = 0;
            button.BackColor = fill;
            button.ForeColor = textColor;
            button.Font = new Font(UiFont, 9.0f, FontStyle.Bold);
            button.Size = new Size(124, 42);
            button.Margin = new Padding(8, 6, 0, 6);
            button.Cursor = Cursors.Hand;
            return button;
        }

        private void Submit()
        {
            string deviceId = Normalize(deviceIdBox.Text);
            string serial = Normalize(serialBox.Text);
            string mac = Normalize(macBox.Text);
            string ip = Normalize(ipBox.Text);

            if (!IsDeviceId(deviceId))
            {
                ShowError("기기 번호는 rpi-001처럼 영문/숫자/하이픈으로 입력하세요.");
                return;
            }
            if (!System.Text.RegularExpressions.Regex.IsMatch(serial, "^[0-9a-fA-F]{8}$"))
            {
                ShowError("RPi4 시리얼은 8자리 hex여야 합니다.");
                return;
            }
            if (!System.Text.RegularExpressions.Regex.IsMatch(mac, "^([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$"))
            {
                ShowError("MAC 주소 형식을 확인하세요. 예: 88:a2:9e:4f:a9:b1");
                return;
            }
            if (ip.Length > 0 && !System.Text.RegularExpressions.Regex.IsMatch(ip, "^10\\.73\\.0\\.([1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-4])$"))
            {
                ShowError("예약 IP는 10.73.0.x 대역이어야 합니다. 비우면 자동 할당됩니다.");
                return;
            }

            Request = new CloneRpi4Request
            {
                DeviceId = deviceId.ToLowerInvariant(),
                Serial = serial.ToLowerInvariant(),
                Mac = mac.ToLowerInvariant().Replace("-", ":"),
                Ip = ip
            };
            DialogResult = DialogResult.OK;
            Close();
        }

        private bool IsDeviceId(string value)
        {
            return System.Text.RegularExpressions.Regex.IsMatch(value, "^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]$");
        }

        private string Normalize(string value)
        {
            return (value ?? "").Trim();
        }

        private void ShowError(string message)
        {
            errorLabel.Text = message;
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
            Font = new Font(UiFonts.Family, 8.9f, FontStyle.Bold);
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
            Color fill = Selected ? Color.FromArgb(229, 243, 240) : Color.FromArgb(255, 255, 255);
            Color text = Selected ? Color.FromArgb(0, 82, 72) : Color.FromArgb(43, 52, 63);
            Color icon = Selected ? Color.FromArgb(0, 103, 92) : Color.FromArgb(102, 114, 128);

            using (GraphicsPath path = RoundedRect(new Rectangle(0, 0, Width - 1, Height - 1), 8))
            using (Brush b = new SolidBrush(fill))
            {
                e.Graphics.FillPath(b, path);
            }
            if (Selected)
            {
                using (GraphicsPath path = RoundedRect(new Rectangle(0, 0, Width - 1, Height - 1), 8))
                using (Pen border = new Pen(Color.FromArgb(181, 220, 211)))
                using (Brush accent = new SolidBrush(Color.FromArgb(0, 103, 92)))
                {
                    e.Graphics.DrawPath(border, path);
                    e.Graphics.FillRectangle(accent, 0, 12, 3, Height - 24);
                }
            }
            if (Focused)
            {
                using (Pen focus = new Pen(Color.FromArgb(0, 103, 92), 2))
                {
                    e.Graphics.DrawRectangle(focus, 2, 2, Width - 5, Height - 5);
                }
            }

            DrawIcon(e.Graphics, Icon, new Rectangle(14, 12, 21, 21), icon);
            TextRenderer.DrawText(
                e.Graphics,
                Text,
                Font,
                new Rectangle(46, 0, Width - 54, Height),
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
