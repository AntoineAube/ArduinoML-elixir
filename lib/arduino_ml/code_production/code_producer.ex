defmodule ArduinoML.CodeProducer do

  alias ArduinoML.Application, as: Application

  @doc """
  Returns a string which is the representation in C code of the application.
  """
  def to_code(app = %Application{sensors: sensors, actuators: actuators,
				 states: states}) do
    """
    // generated by ArduinoML #Elixir.

    // Bricks <~> Pins.
    #{sensors ++ actuators |> Enum.map(&brick_declaration/1) |> Enum.join("\n")}
    
    // Setup the inputs and outputs.
    void setup() {
    #{sensors |> Enum.map(fn s -> "  " <> brick_setup(s, :input) end) |> Enum.join("\n")}

    #{actuators |> Enum.map(fn s -> "  " <> brick_setup(s, :output) end) |> Enum.join("\n")}
    }

    // Static setup code.
    int state = LOW;
    int prev = HIGH;
    long time = 0;
    long debounce = 200;

    // States declarations.
    #{states |> Enum.map(fn state -> state_function(state, app) end) |> Enum.join("\n")}
    // This function specifies the first state.
    #{loop_function(app)}
    """
  end

  defp brick_declaration(%{label: label, pin: pin}), do: "int #{brick_label(label)} = #{pin(pin)};"

  defp brick_setup(%{label: label}, stream), do: "pinMode(#{brick_label(label)}, #{brick_label(stream)});"

  defp state_function(%{label: label, actions: actions}, app) do
    relevant_transitions = Enum.filter(app.transitions, fn %{from: from} -> from == label end)

    actions_lines = actions
    |> Enum.map(fn action -> action_declaration(action, app) end)
    |> Enum.map(&("  " <> &1))
    |> Enum.join("\n")
    
    """
    void #{state_function_name(label)}() {
    #{actions_lines}
    
      boolean guard = millis() - time > debounce;
    
    #{transitions_declaration(relevant_transitions, app)} else {
        #{state_function_name(label)}();
      }
    }
    """
  end

  defp action_declaration(%{actuator_label: label, signal: signal},
                          %{actuators: actuators, sensors: sensors}) do
    type = Enum.find(actuators, fn %{label: actuator_label} -> actuator_label == label end).type

    action_declaration(write_function(type), brick_label(label), signal_label(signal, sensors))
  end

  defp action_declaration(write_function, receiver, signal) do
    "#{write_function}(#{receiver}, #{signal});"
  end
  
  defp transitions_declaration(transitions, app) do
    transitions_declaration(transitions, app, true)
  end

  def transitions_declaration([], _, _), do: ""
  def transitions_declaration([%{to: to, on: assertions} | others], app, is_first) do
    partial_condition = assertions
    |> Enum.map(fn assertion -> condition(assertion, app) end)
    |> Enum.join(" && ")
    
    "#{condition_keyword(is_first)} (#{partial_condition} && guard) {\n" <>
    "    time = millis();\n" <>
    "    #{state_function_name(to)}();\n" <>
    "  }" <> transitions_declaration(others, app, false)
  end

  defp condition_keyword(false), do: " else if"
  defp condition_keyword(true), do: "  if"

  defp comparison(:equals), do: "=="
  defp comparison(:lower_than), do: "<"
  defp comparison(:greater_than), do: ">"

  defp condition(%{sensor_label: label, signal: signal, comparison: sign}, %{sensors: sensors}) do
    "#{signal_label(label, sensors)} #{comparison(sign)} #{signal_label(signal)}"
  end

  defp loop_function(app) do
    "void loop() {\n" <>
    "  #{app |> Application.initial |> state_function_name}();\n" <>
    "}"
  end
  
  defp write_function(:digital), do: "digitalWrite"
  defp write_function(:analogic), do: "analogWrite"

  defp read_function(:digital), do: "digitalRead"
  defp read_function(:analogic), do: "analogRead"
  
  defp state_function_name(label), do: "state_" <> state_label(label)

  defp state_label(label) when is_atom(label), do: label |> Atom.to_string |> String.downcase
  defp state_label(label) when is_binary(label), do: String.downcase(label)

  defp brick_label(label) when is_atom(label), do: label |> Atom.to_string |> String.upcase
  defp brick_label(label) when is_binary(label), do: String.upcase(label)

  defp signal_label(label, _) when label in [:low, :high] or is_integer(label), do: signal_label(label)
  defp signal_label(label, sensors) do
    type = Enum.find(sensors, fn %{label: sensor_label} -> sensor_label == label end).type

    "#{read_function(type)}(#{brick_label(label)})"
  end
  
  defp signal_label(label) when label in [:low, :high], do: label |> Atom.to_string |> String.upcase
  defp signal_label(label) when is_integer(label), do: Integer.to_string(label)
    
  defp pin(value) when is_integer(value), do: Integer.to_string(value)
end
