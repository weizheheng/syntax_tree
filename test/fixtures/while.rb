%
while foo
end
%
while foo
  bar
end
-
bar while foo
%
while fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  bar
end
%
foo = while bar do baz end
-
foo = (baz while bar)
%
while foo += 1
  foo
end
%
while (foo += 1)
  foo
end
%
while foooooooooooooooooooooo || barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
  something
end
-
while foooooooooooooooooooooo ||
        barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? do |bar|
          bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
        end
  something
end
%
while barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
  something
end
-
while barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar|
        bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
      }
  something
end
