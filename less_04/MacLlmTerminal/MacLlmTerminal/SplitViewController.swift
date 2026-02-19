import Cocoa

// MARK: - Split View Controller

final class SplitViewController: NSSplitViewController {
    
    var settingsViewController: SettingsViewController?
    var chatViewController: ChatViewController?
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupSplitView()
    }
    
    private func setupSplitView() {
        // Создаём левую панель - чат
        let chatVC = ChatViewController()
        let chatItem = NSSplitViewItem(viewController: chatVC)
        chatItem.minimumThickness = 400
        chatItem.collapseBehavior = .useConstraints
        
        // Создаём правую панель - настройки
        let settingsVC = SettingsViewController()
        settingsViewController = settingsVC
        let settingsItem = NSSplitViewItem(viewController: settingsVC)
        settingsItem.minimumThickness = 350
        settingsItem.maximumThickness = 500
        settingsItem.isCollapsed = false
        settingsItem.canCollapse = true
        
        // Добавляем элементы
        addSplitViewItem(chatItem)
        addSplitViewItem(settingsItem)
        
        chatViewController = chatVC
        
        // Настраиваем divider
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "MainSplitView"
    }
    
    func toggleSettingsPanel() {
        guard let settingsItem = splitViewItems.last else { return }
        settingsItem.isCollapsed.toggle()
    }
    
    var isSettingsPanelVisible: Bool {
        guard let settingsItem = splitViewItems.last else { return false }
        return !settingsItem.isCollapsed
    }
}


final class TestScrollVC: NSViewController {
    private enum Constants {
        static let llmUrl = "https://routerai.ru/api/v1/chat/completions"
        static let longText = """
                               Отличный вопрос! Погода в Калининграде в апреле — это классическая \"весна с характером\", переходный месяц, когда зима окончательно сдаёт позиции, но капризы ещё возможны. Вот подробная характеристика:\n\n### 🌡️ Температура:\n- **Средняя дневная температура**: +8°C до +12°C, но возможны колебания от **0°C до +18°C**.\n- **Ночью**: +2°C до +5°C, иногда бывают слабые заморозки (особенно в начале месяца).\n- **К концу апреля** обычно становится ощутимо теплее, особенно в солнечные дни.\n\n### 🌧️ Осадки и облачность:\n- **Дожди** часты, но обычно непродолжительные (морось или кратковременные ливни). Апрель — один из самых **сухих** месяцев в году по сравнению с летом, но влажность высокая.\n- **Солнечных дней** становится больше, чем в марте, но переменная облачность — норма.\n- **Возможен мокрый снег или снежная крупа** в первой половине месяца, особенно ночью.\n\n### 💨 Ветер:\n- Ветер часто **умеренный или сильный** (Калининград находится у Балтийского моря, поэтому ветра — обычное явление).\n- Может ощущаться прохлада даже при плюсовой температуре из-за влажности и ветра (\"сырая погода\").\n\n### 🌸 Природа и световой день:\n- **Середина-конец апреля** — начало **цветения** (первоцветы, магнолии, позже — сакура в Ботаническом саду).\n- **Световой день** быстро увеличивается: к концу месяца солнце светит **около 14 часов**.\n- Море ещё **очень холодное** (+4°C...+6°C), купаться рано.\n\n### 📊 Статистика (средние показатели):\n- **Средняя температура месяца**: около +6°C.\n- **Количество солнечных дней**: 7–10 за месяц.\n- **Осадков**: 40–50 мм (меньше, чем летом).\n\n### ✅ Что важно знать туристам и жителям:\n1. **Одежда** — лучше **слоёная**: ветровка/дождевик, свитер, зонт. Обувь — непромокаемая.\n2. **Апрель непредсказуем** — утром может быть солнце, а после обеда — дождь с ветром.\n3. **Идеально для прогулок** без летней толкучки: парки (например, Центральный парк) начинают зеленеть, но комаров ещё нет.\n4. **Исторически** в апреле бывали как **аномально тёплые** дни (до +20°C), так и **поздние снегопады** (например, в 2017 году).\n\n### 🗺️ Контекст:\nКлимат Калининграда — **умеренный морской**, с мягкой зимой и прохладным летом. Апрель — это как \"облегчённая версия\" мая: уже не зима, но ещё не стабильное тепло. Если повезёт с антициклоном, погода может быть **удивительно солнечной и тёплой**.\n\n**Кратко:** Апрель в Калининграде — **прохладный, ветреный, с частой сменой солнца и дождей**. Весна здесь проявляется скорее в удлинении дня и цветах, чем в жаре. Лучше быть готовым ко всему! 😊\n\nНужны ли уточнения или интересны сравнения с другими городами?
            """
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true       // Включаем вертикальный скролл
        scrollView.hasHorizontalScroller = false    // Обычно горизонтальный не нужен при переносе
        scrollView.autohidesScrollers = false       // Чтобы скролл был виден всегда (опционально)
        scrollView.borderType = .bezelBorder

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer()
        
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        
        // 2. Настраиваем TextView
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false // ❗ КРИТИЧНО: должно быть false
        textView.isVerticallyResizable = true      // Разрешаем рост по высоте
        textView.autoresizingMask = [.width]       // Растягиваем по ширине, но не по высоте

        // 3. Связываем их
        scrollView.documentView = textView

        // 4. Добавляем ScrollView в иерархию (а не TextView напрямую!)
        view.addSubview(scrollView)
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 300) // ❗ Фиксированная высота или ограничение относительно superview
        ])
        
//        textView.
    }
}

import Cocoa

class ViewController: NSViewController {

    // 1. Объявляем переменные
    private var scrollView: NSScrollView!
    private var textView: NSTextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Настраиваем фон основного вида (для наглядности)
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        setupScrollView()
        setupTextView()
        setupConstraints()
        fillWithLongText()
    }

    // 2. Настройка ScrollView
    private func setupScrollView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true       // Включаем вертикальный скролл
        scrollView.hasHorizontalScroller = false    // Выключаем горизонтальный (текст переносится)
        scrollView.autohidesScrollers = false       // Скролл виден всегда (можно поставить true)
        scrollView.borderType = .bezelBorder        // Рамка вокруг поля ввода
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        // Важно: разрешаем scrollView растягиваться по ширине
        scrollView.autoresizingMask = [.width, .height]
    }

    // 3. Настройка TextView
    private func setupTextView() {
        // Создаем TextView. Он автоматически создаст TextContainer внутри.
        textView = NSTextView()
        
        // --- КРИТИЧЕСКИ ВАЖНЫЕ НАСТРОЙКИ ДЛЯ СКРОЛЛА И ПЕРЕНОСА ---
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false               // Простой текст (легче настраивать перенос)
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        
        // Настройки контейнера текста
        textView.textContainer?.widthTracksTextView = true   // Ширина зависит от ScrollView
        textView.textContainer?.heightTracksTextView = false // ❗ Высота НЕ зависит (иначе скролл не сработает)
        textView.textContainer?.lineBreakMode = .byWordWrapping // Перенос по словам
        
        // Разрешаем TextView расти по вертикали внутри скролла
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width] // Растягиваем по ширине скролла
        
        // Убираем лишние отступы (опционально)
//        textView.textContainer?.containerOrigin = CGPoint(x: 4, y: 4)
        
        // --- СВЯЗЫВАЕМ TextView И ScrollView ---
        scrollView.documentView = textView
    }

    // 4. Auto Layout (Ограничения только для ScrollView!)
    private func setupConstraints() {
        view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.heightAnchor.constraint(equalToConstant: 300) // Фиксированная высота для демонстрации скролла
        ])
    }

    // 5. Добавляем много текста для проверки скролла
    private func fillWithLongText() {
        var longText = ""
        for i in 1...50 {
            longText += "Это строка номер \(i). Текст должен автоматически переноситься на новую строку, если он не помещается по ширине. Когда текста станет много, появится вертикальная прокрутка справа.\n\n"
        }
        textView.string = longText
    }
}
