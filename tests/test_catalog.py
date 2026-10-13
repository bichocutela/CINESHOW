import unittest
from backend.catalog import Source,merge,parse_cards,parse_chapters,DooplayAdapter
class CatalogTests(unittest.TestCase):
 def test_merge_keeps_sources_and_does_not_merge_years_or_types(self):
  a=Source('rtfilmes','1','https://rtfilmes.com/filme/a/','Ação','movie',2026)
  b=Source('tontons','2','https://tontonsfilmeurs.com/filme/a/','Acao','movie',2026)
  c=Source('tontons','3','https://tontonsfilmeurs.com/filme/a/','Acao','movie',2025)
  result=merge([a,b,c,a]);self.assertEqual(len(result),2);self.assertEqual(len(result[0]['sources']),2)
 def test_cards_extract_ids_year_and_skip_foreign_links(self):
  markup='''<article id="post-featured-123"><img data-src="https://example.com/cover.jpg"><h3><a href="https://rtfilmes.com/filme/demo/">Demo &amp; Co</a></h3><span>Oct. 12, 2026</span></article>'''
  items=parse_cards(markup,'rtfilmes','https://rtfilmes.com');self.assertEqual(items[0].year,2026);self.assertEqual(items[0].title,'Demo & Co')
  self.assertEqual(parse_cards(markup,'rtfilmes','https://tontonsfilmeurs.com'),[])
 def test_chapter_variants_are_not_lost(self):
  s="<iframe src='/ast/OnW/?zy=1&date=20261012&y=x'></iframe><iframe src='/ast/OnW/?zy=1&date=20261012_1&y=z'></iframe>"
  self.assertEqual([x['id'] for x in parse_chapters(s)],['20261012','20261012_1'])
 def test_invalid_player_cannot_change_route(self):
  a=DooplayAdapter('rtfilmes')
  try:
   with self.assertRaises(ValueError):a.player({'post':'../../','type':'movie','source':'1'})
  finally:a.close()
if __name__=='__main__':unittest.main()
