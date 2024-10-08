package program

import (
	"fmt"
	"log"
	"math"

	_ "embed"

	"github.com/bvisness/BretVictorsWorstNightmare/server/src/utils"
	lua "github.com/yuin/gopher-lua"
)

//go:embed tictactoe.lua
var TicTacToe string

//go:embed calculator.lua
var Calculator string

//go:embed vectors.lua
var Vectors string

//go:embed pprint.lua
var PPrint string

type Program struct {
	Name   string
	Source string
}

type Instance struct {
	L      *lua.LState
	Data   Data // will be of type TypeTable
	Tapped string

	Program *Program
}

type Data struct {
	Type DataType `msgpack:"type"`

	TableValue  []MapEntry `msgpack:"tablevalue"`
	BoolValue   bool       `msgpack:"boolvalue"`
	NumberValue float64    `msgpack:"numbervalue"`
	StringValue string     `msgpack:"stringvalue"`
}

type MapEntry struct {
	KeyType   KeyType `msgpack:"keytype"`
	StringKey string  `msgpack:"stringkey"`
	NumberKey float64 `msgpack:"numberkey"`
	Value     Data    `msgpack:"value"`
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

type Vec3 [3]float64
type Quat [4]float64

func (v Vec3) Len() float64 {
	return math.Sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
}

func (v Vec3) Normalized() Vec3 {
	l := v.Len()
	return Vec3{v[0] / l, v[1] / l, v[2] / l}
}

func (v Vec3) Dot(b Vec3) float64 {
	return v[0]*b[0] + v[1]*b[1] + v[2]*b[2]
}

func (v Vec3) Cross(b Vec3) Vec3 {
	return Vec3{
		(v[1] * b[2]) - (v[2] * b[1]),
		(v[2] * b[0]) - (v[0] * b[2]),
		(v[0] * b[1]) - (v[1] * b[0]),
	}
}

func (q Quat) Normalized() Quat {
	norm := math.Sqrt(q[0]*q[0] + q[1]*q[1] + q[2]*q[2] + q[3]*q[3])
	return Quat{q[0] / norm, q[1] / norm, q[2] / norm, q[3] / norm}
}

type Object struct {
	Type  ObjectType `msgpack:"type"`
	ID    string     `msgpack:"id"`
	Pos   Vec3       `msgpack:"pos"`
	Rot   Quat       `msgpack:"rot"`
	Size  Vec3       `msgpack:"size"`
	Color string     `msgpack:"color"`

	// for ObjectTypeText
	Text      string  `msgpack:"text"`
	TextSize  float64 `msgpack:"textsize"`
	TextAlign string  `msgpack:"textalign"`
	TextWrap  bool    `msgpack:"textwrap"`

	Children []Object `msgpack:"children"`
}

type ObjectType int

const (
	ObjectTypeAnchor ObjectType = iota
	ObjectTypeBox
	ObjectTypeSphere
	ObjectTypeCylinder
	ObjectTypeCone
	ObjectTypeText
	ObjectTypeTriggerBox
)

var objtype2go = map[string]ObjectType{
	"":           ObjectTypeAnchor,
	"anchor":     ObjectTypeAnchor,
	"box":        ObjectTypeBox,
	"sphere":     ObjectTypeSphere,
	"cylinder":   ObjectTypeCylinder,
	"cone":       ObjectTypeCone,
	"text":       ObjectTypeText,
	"triggerbox": ObjectTypeTriggerBox,
}

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

	err := L.DoString(PPrint)
	if err != nil {
		return nil, fmt.Errorf("failed to include pprint: %w", err)
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
		"gettapped": func(L *lua.LState) int {
			if i.Tapped != "" {
				L.Push(lua.LString(i.Tapped))
			} else {
				L.Push(lua.LNil)
			}
			return 1
		},
		"cleartap": func(L *lua.LState) int {
			i.Tapped = ""
			return 0
		},
	})

	err = L.DoString(p.Source)
	if err != nil {
		return nil, fmt.Errorf("failed to run Lua source: %w", err)
	}

	return i, nil
}

func (i *Instance) Init() error {
	init := i.L.GetGlobal("ARInit")
	if init == lua.LNil {
		return nil
	}

	return i.L.CallByParam(lua.P{
		Fn:      init,
		Protect: true,
	})
}

func (i *Instance) RenderScene() (Object, error) {
	render := i.L.GetGlobal("ARRenderScene")
	if render == lua.LNil {
		return Object{}, nil
	}

	err := i.L.CallByParam(lua.P{
		Fn:      render,
		NRet:    1,
		Protect: true,
	})
	if err != nil {
		return Object{}, err
	}

	ret := i.L.Get(-1)
	i.L.Pop(1)

	if object, ok := Lua2Object(i.L, ret); ok {
		return object, nil
	} else {
		return Object{}, nil
	}
}

func (i *Instance) Tap(id string) {
	i.Tapped = id
}

func Lua2Object(L *lua.LState, lobj lua.LValue) (Object, bool) {
	objType := lua.LVAsString(L.GetField(lobj, "type"))
	id := lua.LVAsString(L.GetField(lobj, "id"))
	pos := getVec3(L, L.GetField(lobj, "pos"), Vec3{0, 0, 0})
	size := getVec3(L, L.GetField(lobj, "size"), Vec3{1, 1, 1})
	color := lua.LVAsString(L.GetField(lobj, "color"))
	text := lua.LVAsString(L.GetField(lobj, "text"))
	textsize := lua.LVAsNumber(L.GetField(lobj, "textsize"))
	textalign := lua.LVAsString(L.GetField(lobj, "textalign"))
	textwrap := lua.LVAsBool(L.GetField(lobj, "textwrap"))

	objTypeGo, ok := objtype2go[objType]
	if !ok {
		log.Printf("WARNING! Unrecognized object type '%s'", objType)
		return Object{}, false
	}

	rot := Quat{0, 0, 0, 1}
	if rotTable, ok := L.GetField(lobj, "rot").(*lua.LTable); ok {
		if L.GetField(rotTable, "axis") != lua.LNil {
			axis := getVec3(L, L.GetField(rotTable, "axis"), Vec3{1, 0, 0})
			angle := float64(lua.LVAsNumber(L.GetField(rotTable, "angle")))

			axisNorm := math.Sqrt(axis[0]*axis[0] + axis[1]*axis[1] + axis[2]*axis[2])
			axis = Vec3{axis[0] / axisNorm, axis[1] / axisNorm, axis[2] / axisNorm}
			sineOfRotation := math.Sin(angle / 2)

			rot = Quat{
				axis[0] * sineOfRotation,
				axis[1] * sineOfRotation,
				axis[2] * sineOfRotation,
				math.Cos(angle / 2),
			}
		} else if L.GetField(rotTable, "from") != lua.LNil {
			from := getVec3(L, L.GetField(rotTable, "from"), Vec3{1, 0, 0}).Normalized()
			to := getVec3(L, L.GetField(rotTable, "to"), Vec3{1, 0, 0}).Normalized()

			cross := from.Cross(to)
			dot := from.Dot(to)
			rot = Quat{
				cross[0],
				cross[1],
				cross[2],
				1 + dot,
			}.Normalized()
		}
	}

	if textsize == 0 {
		textsize = 0.05
	}

	obj := Object{
		Type:      objTypeGo,
		ID:        id,
		Pos:       pos,
		Rot:       rot,
		Size:      size,
		Color:     color,
		Text:      text,
		TextSize:  float64(textsize),
		TextAlign: textalign,
		TextWrap:  textwrap,
	}

	for i := 1; i <= L.ObjLen(lobj); i++ {
		lchild := L.GetTable(lobj, lua.LNumber(i))
		if child, ok := Lua2Object(L, lchild); ok {
			obj.Children = append(obj.Children, child)
		}
	}
	return obj, true
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

func getVec3(L *lua.LState, v lua.LValue, defaultValue Vec3) Vec3 {
	if v == lua.LNil {
		return defaultValue
	}
	if v.Type() == lua.LTNumber {
		n := float64(lua.LVAsNumber(v))
		return Vec3{n, n, n}
	}
	return Vec3{
		float64(lua.LVAsNumber(L.GetTable(v, lua.LNumber(1)))),
		float64(lua.LVAsNumber(L.GetTable(v, lua.LNumber(2)))),
		float64(lua.LVAsNumber(L.GetTable(v, lua.LNumber(3)))),
	}
}
