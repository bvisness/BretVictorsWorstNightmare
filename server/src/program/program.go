package program

import (
	"fmt"

	"github.com/bvisness/BretVictorsWorstNightmare/server/src/utils"
	lua "github.com/yuin/gopher-lua"
)

type Program struct {
	Name   string
	Source string
}

type Instance struct {
	L    *lua.LState
	Data Data // will be of type TypeTable

	Program *Program
}

type Data struct {
	Type DataType

	TableValue  []MapEntry
	BoolValue   bool
	NumberValue float64
	StringValue string
}

type MapEntry struct {
	KeyType   KeyType
	StringKey string
	NumberKey float64
	Value     Data
}

type KeyType int
type DataType int

const (
	KeyTypeString KeyType = iota + 1
	KeyTypeNumber
)

const (
	TypeNil DataType = iota
	TypeTable
	TypeBool
	TypeNumber
	TypeString
)

func splitMapKey(key any) (KeyType, string, float64, bool) {
	switch k := key.(type) {
	case string:
		return KeyTypeString, k, 0, true
	case lua.LString:
		return KeyTypeString, k.String(), 0, true
	case float64:
		return KeyTypeNumber, "", k, true
	case lua.LNumber:
		return KeyTypeNumber, "", float64(k), true
	}
	return 0, "", 0, false
}

func (d *Data) MapGet(key any) (*Data, bool) {
	utils.Assert(d.Type == TypeTable)

	keyType, keyString, keyNumber, ok := splitMapKey(key)
	if !ok {
		return nil, false
	}

	for i := range d.TableValue {
		entry := &d.TableValue[i]
		matchesString := entry.KeyType == KeyTypeString && keyType == KeyTypeString && entry.StringKey == keyString
		matchesNumber := entry.KeyType == KeyTypeNumber && keyType == KeyTypeNumber && entry.NumberKey == keyNumber
		if matchesString || matchesNumber {
			return &entry.Value, true
		}
	}
	return nil, false
}

func (d *Data) MapSet(key any, value Data) (*Data, bool) {
	keyType, keyString, keyNumber, ok := splitMapKey(key)
	if !ok {
		return nil, false
	}

	entry := MapEntry{KeyType: keyType, Value: value}
	if keyType == KeyTypeString {
		entry.StringKey = keyString
	} else if keyType == KeyTypeNumber {
		entry.NumberKey = keyNumber
	}
	d.TableValue = append(d.TableValue, entry)
	return &d.TableValue[len(d.TableValue)-1].Value, true
}

func Instantiate(p *Program) (*Instance, error) {
	L := lua.NewState()
	i := &Instance{
		L: L,
		Data: Data{
			Type: TypeTable,
		},

		Program: p,
	}

	ar := L.NewTable()
	L.SetGlobal("ar", ar)
	L.SetFuncs(ar, map[string]lua.LGFunction{
		"getdata": func(L *lua.LState) int {
			L.Push(Data2Lua(L, &i.Data))
			return 1
		},
		"setdata": func(L *lua.LState) int {
			// Walk the path of keys / indices, creating tables as necessary
			data := &i.Data
			for i := 1; i <= L.GetTop()-1; i++ {
				lkey := L.Get(i)
				switch lkey.Type() {
				case lua.LTString, lua.LTNumber:
					if data.Type == TypeNil {
						data.Type = TypeTable
					}

					if newdata, ok := data.MapGet(lkey); ok {
						data = newdata
					} else {
						data, ok = data.MapSet(lkey, Data{})
						if !ok {
							L.RaiseError("bad key type for table: %s", lkey.Type().String())
							return 0
						}
					}
				default:
					L.RaiseError("bad key / index type: %s", lkey.Type().String())
					return 0
				}
			}

			ldata, err := Lua2Data(L, L.Get(L.GetTop()))
			if err != nil {
				L.RaiseError("failed to set AR data: %s", err.Error())
			}
			*data = ldata
			return 0
		},
	})

	err := L.DoString(p.Source)
	if err != nil {
		return nil, fmt.Errorf("failed to run Lua source: %w", err)
	}

	return i, nil
}

func (i *Instance) Init() error {
	init := i.L.GetGlobal("ARInit")
	if init != lua.LNil {
		err := i.L.CallByParam(lua.P{
			Fn:      init,
			Protect: true,
		})
		return err
	}
	return nil
}

func Data2Lua(L *lua.LState, d *Data) lua.LValue {
	switch d.Type {
	case TypeNil:
		return lua.LNil
	case TypeTable:
		t := L.NewTable()
		for i := range d.TableValue {
			entry := &d.TableValue[i]
			var key lua.LValue
			switch entry.KeyType {
			case KeyTypeString:
				key = lua.LString(entry.StringKey)
			case KeyTypeNumber:
				key = lua.LNumber(entry.NumberKey)
			}
			L.SetTable(t, key, Data2Lua(L, &entry.Value))
		}
		return t
	case TypeBool:
		return lua.LBool(d.BoolValue)
	case TypeNumber:
		return lua.LNumber(d.NumberValue)
	case TypeString:
		return lua.LString(d.StringValue)
	default:
		panic(fmt.Errorf("unknown data type %d", d.Type))
	}
}

func Lua2Data(L *lua.LState, v lua.LValue) (Data, error) {
	if v == nil || v.Type() == lua.LTNil {
		return Data{}, nil
	}

	switch v.Type() {
	case lua.LTTable:
		d := Data{Type: TypeTable}
		t := v.(*lua.LTable)
		var foreachErr error
		t.ForEach(func(key, value lua.LValue) {
			var entry MapEntry
			switch key.Type() {
			case lua.LTString:
				entry = MapEntry{
					KeyType:   KeyTypeString,
					StringKey: string(key.(lua.LString)),
				}
			case lua.LTNumber:
				entry = MapEntry{
					KeyType:   KeyTypeNumber,
					NumberKey: float64(key.(lua.LNumber)),
				}
			default:
				panic(fmt.Errorf("unknown key type %s", key.Type().String()))
			}
			entry.Value, foreachErr = Lua2Data(L, value)
			if foreachErr != nil {
				return
			}
			d.TableValue = append(d.TableValue, entry)
		})
		if foreachErr != nil {
			return Data{}, foreachErr
		}
		return d, nil
	case lua.LTBool:
		return Data{Type: TypeBool, BoolValue: bool(v.(lua.LBool))}, nil
	case lua.LTNumber:
		return Data{Type: TypeNumber, NumberValue: float64(v.(lua.LNumber))}, nil
	case lua.LTString:
		return Data{Type: TypeString, StringValue: string(v.(lua.LString))}, nil
	}
	return Data{}, fmt.Errorf("cannot convert value of type %s to AR data", v.Type().String())
}
