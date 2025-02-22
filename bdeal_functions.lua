--[[ Набор функций, которые могут быть полезными при работе с bdeal.

Использование: Сохранить файл в папку с Вашими скриптами, затем в начале скрипта добавить dofile("bdeal_functions.lua")

Функции в библиотеке:
tricks_correction(contract, tricks_taken) - пытается получить коррекцию за розыгрыш и вист человеками. За основу взято соотношение от Ричарда Павличека. 
Выдает 0 или +-1 для каждой сдачи, то есть, результат надо прибавить к результату функции tricks основнойпрограммы и затем отправить в stats.
Использовать надо аккуратно, у меня есть большие сомнения в генераторе случайных чисел (см. текст примечаний в функции) и иногда она будет давать очевидный бред:
Если у севера будет 13 пик, то в контракте 7п она иногда будет давать отрицательную коррекцию. Также, чем сильнее зафиксированы руки, тем меньше на нее можно полагаться

 have_stopper(N:S()) - возвращает true если у севера есть задержка в пике
 have_cuebid(N:S()) - возвращает true если у севера есть кюбид любого класса в пике
 
 total_points(level, -- Уровень контракта (1 - 7)
						suit, -- Масть (C, D, H, S, NT)
						tricks, -- Взято взяток (0- 13)
						vul, -- до зоны (false) или в зоне (true), если опустить - то до зоны
						doubled, -- Была ли контра true/false, можно опустить
						redoubled -- Была ли реконтра true/false, можно опустить
						) - подсчет тотальных пунктов
						
total_to_imp(delta) - перевод тотальных пунктов в импы
--]]

--[[ Таблица вероятности накатить взятку от Ричарда Павличека --]]
prob_table = {
	["1C"] = 0,
	["1D"] = 0.36,
	["1H"] = 0.06,
	["1S"] = 0.18,
	["1NT"] = 0.3 ,
	["2C"] = 0.12,
	["2D"] = 0.1,
	["2H"] = 0.08,
	["2S"] = 0.1,
	["2NT"] = 0.2,
	["3C"] = 0.03,
	["3D"] = 0.05,
	["3H"] = 0.07,
	["3S"] = 0.1,
	["3NT"] = 0.12,
	["4C"] = 0.11,
	["4D"] = 0.06,
	["4H"] = -0.03,
	["4S"] = 0.01,
	["4NT"] = 0.11,
	["5C"] = 0.02,
	["5D"] = 0.02,
	["5H"] = 0.11,
	["5S"] = 0.05,
	["5NT"] = -0.17,
	["6C"] = -0.06,
	["6D"] = -0.06,
	["6H"] = -0.04,
	["6S"] = -0.07,
	["6NT"] = -0.08,
	["7C"] = -0.23,
	["7D"] = -0.11,
	["7H"] = -0.05,
	["7S"] = -0.13,
	["7NT"] = -0.04

}

imp_table = {
	10, 40, 80, 120, 160,
	210, 260, 310, 360, 420,
	490, 590, 740, 890, 1090,
	1290, 1490, 1740, 1990, 2240,
	2490, 2990, 3490, 3990, 100000
}
-- Инициализация генератора
math.randomseed(os.time())
--math.randomseed( tonumber(tostring(os.time()):reverse():sub(1,6)) )

--Перевод bool в число (служебная)
function bool_to_number(value)
  return value and 1 or 0
end

--[[ Есть корректировка в данной сдаче или нет. Вызов: correction("1NT", 8) - выдаст 0 или 1 с вероятностью 30% (накатили взятку или нет). 
Параметр tricks_taken можно опустить, он нужен для отсечки отрицательных взяток или 14 взяток --]]
function tricks_correction(contract, tricks_taken)
--[[ В функции есть баг при работе на нескольких потоках. Некорректная реализация инициализации ГСЧ. Поэтому, при многопоточных вычислениях результат 
работы будет одинаковым (но это не точно, иногда - разный). Как это обойти я не знаю, на потоки делится в основной программе. 
Workaround: запускать программу с одним потоком (ключ -j 1) --]]
	local p = prob_table[contract]
	local correction
	
	if tricks_taken == nil then tricks_taken = 7 end
	if math.abs(p) < 0.001 then -- Ловим нулевое отклонение
		return 0
	end
	correction = p / math.abs(p) * bool_to_number(math.random() <= math.abs(p))
	
	if tricks_taken + correction > 13 or tricks_taken + correction < 0 then
		correction = 0
	end
	return correction
end

-- Есть ли задержка в масти. Вызов: have_stopper(N:S()) - есть ли задержка пик у Севера
function have_stopper(suit)
	return suit:hcp() + suit:count() >= 5
end

-- Есть ли кюбид в масти. Вызов: have_cuebid(N:S()) - есть ли пиковый кюбид у Севера (любого класса)
function have_cuebid(suit)
	return suit:points(1, 1) >= 1 or suit:count() <= 1
end

-- подсчет тотальных пунктов за контракт
function total_points(level, -- Уровень контракта (1 - 7)
						suit, -- Масть (C, D, H, S, NT)
						tricks, -- Взято взяток (0- 13)
						vul, -- до зоны (false) или в зоне (true), если опустить - то до зоны
						doubled, -- Была ли контра true/false, можно опустить
						redoubled -- Была ли реконтра true/false, можно опустить
						)
	if vul == nil then vul = false end
	if doubled == nil then doubled = false end
	if redoubled == nil then redoubled = false end
	if redoubled then doubled = true end
	
	local base_score = 0
	local over_score = 0
	local bonus = 0
	local trick_price
	
	if level + 6 <= tricks then -- выиграли контракта
		if suit == "C" or suit == "D" then
			trick_price = 20
		else
			trick_price = 30
		end
		
		if suit == "NT" then
			base_score = level * trick_price + 10
		else
			base_score = level * trick_price
		end
		
		if doubled then base_score = base_score * 2 end
		if redoubled then base_score = base_score * 2 end
		
		bonus = 50 * 2 ^ (bool_to_number(doubled) + bool_to_number(redoubled))
		if base_score >= 100 then -- гейм
			if vul then
				bonus = bonus + 450
			else
				bonus = bonus + 250
			end
		end
		
		if level == 6 then -- малый шлем
			if vul then 
				bonus = bonus + 750
			else
				bonus = bonus + 500
			end
		end
		if level == 7 then -- большой шлем
			if vul then 
				bonus = bonus + 1500
			else
				bonus = bonus + 1000
			end
		end
		
		-- считаем овера
		if doubled then
			trick_price = 100 * 2 ^ (bool_to_number(vul) + bool_to_number(redoubled))
		end
		over_score = (tricks - level - 6) * trick_price	
	else -- подсад
		if doubled then
			if vul then
				if level + 6 - tricks == 1 then
					base_score = -200
				else
					base_score = -200 - 300 * (level + 5 - tricks)
				end
			else
				if level + 6 - tricks == 1 then
					base_score = -100
				elseif level + 6 - tricks == 2 then
					base_score = -300
				elseif level + 6 - tricks == 3 then
					base_score = -500
				else
					base_score = -500 - 300 * (level + 3 - tricks)
				end
			end
		else
			base_score = -50 * (level + 6 - tricks) * 2 ^ bool_to_number(vul)
		end
		
		if redoubled then base_score = base_score * 2 end
	end
	return base_score + over_score + bonus
end

-- перевод тотальных пунктов в импы
function total_to_imp(delta)
	local tmp
	tmp = math.abs(delta)
	if tmp < 0.00001 then return 0 end
	local i = 1
	while tmp > imp_table[i] do
		i = i + 1
	end
	return (i - 1) * tmp / delta
end